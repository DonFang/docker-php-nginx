FROM php:7.1-fpm-jessie

LABEL name="nginx-php" \
    maintainer="Don.Fang <fangweidong@qq.com>" \
    version="1.0"

WORKDIR /app
COPY . .

RUN mv /etc/apt/sources.list /etc/apt/sources.list.bak && mv sources.list /etc/apt/ 

# 更新源，并安装必需依赖
RUN apt-get update \
    && apt-get install --no-install-recommends --no-install-suggests -y \
        wget unzip g++ git \
    && apt-get clean && rm -r /var/lib/apt/lists/*


# 定义依赖版本号
ENV NGINX_VERSION="1.12.2" \
    NGINX_OPENSSL_VERSION="1.0.2n" \
    NGINX_CT_VERSION="1.3.2"

# Nginx 和 PHP 在安装编译时的依赖
ENV NGINX_PHP_DEPS \
    # 用于 nginx rewrite 模块
    libpcre3-dev \
    # 用于 nginx zlib 模块
    zlib1g-dev \
    # mongodb 扩展依赖
    libssl-dev \
    # gd 依赖
    libjpeg62-turbo-dev libpng12-dev libfreetype6-dev \
    # soap 依赖
    libxml2-dev \
    # intl 依赖
    libicu-dev \
    # mcrypt 依赖
    libmcrypt-dev \
    # pdo_pgsql 依赖
    libpq-dev \
    # xsl 依赖
    libxslt1-dev


#########################################
#           编译安装 Nginx               #
#########################################
RUN set -eux; \
      \
      cd /usr/local/src; \
      \
      # 安装开发依赖
      apt-get update -y; \
      apt-get install --no-install-recommends --no-install-suggests -y $NGINX_PHP_DEPS; \
	  apt-get clean; \
      rm -r /var/lib/apt/lists/*; \
      \
      # 下载并解压 nginx 源码
      wget -O nginx.tar.gz -c http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz; \
      tar zxf nginx.tar.gz; \
      \
      # 下载并解压 openSSL 源码
      wget -O openssl.tar.gz -c https://www.openssl.org/source/openssl-${NGINX_OPENSSL_VERSION}.tar.gz; \
      tar zxf openssl.tar.gz; \
      \
      # 下载并解压 nginx-ct 源码
      wget -O nginx-ct.zip -c https://github.com/grahamedgecombe/nginx-ct/archive/v${NGINX_CT_VERSION}.zip; \
      unzip nginx-ct.zip; \
      \
      # 编译安装 nginx
      cd nginx-${NGINX_VERSION}; \
      ./configure \
          --add-module=../nginx-ct-${NGINX_CT_VERSION} \
          --with-openssl=../openssl-${NGINX_OPENSSL_VERSION} \
          --with-http_v2_module \
          --with-http_ssl_module \
          --with-http_gzip_static_module \
          # 用于替换 header 及日志中的真实用户 IP 
          --with-http_realip_module \
      ; \
      make -j "$(nproc)"; \
      make install; \
      \
      # 清理临时文件
      rm -rf /usr/local/src/*;


#########################################
#           安装 PHP 扩展                #
#########################################
RUN set -eux; \
    \
    cd /usr/local/src; \
    \
    # 安装 PHP 第三方扩展
    pecl install redis; \
    pecl install mongodb; \
    \
    # 安装 PHP 自带的依赖
    docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-jpeg-dir=/usr/include/; \
    docker-php-ext-install -j$(nproc) soap gd intl mcrypt zip pdo_mysql pdo_pgsql xsl; \
    \
    # 启用扩展
    docker-php-ext-enable mongodb opcache redis; \
    \
    rm -rf /tmp/pear;


# 安装 screw-plus
RUN set -eux; \
    \
    cd /usr/local/src; \
    git clone --depth=1 https://github.com/del-xiong/screw-plus.git; \
    cd screw-plus; \
    \
    phpize; \
    ./configure --with-php-config=/usr/local/bin/php-config; \
    sed -i 's|#define CAKEY .*|#define CAKEY "LKtriKZgJPzxd405rKWu3dlFkDfZmUrp"|' php_screw_plus.h; \
    make -j "$(nproc)"; \
    make install; \
    echo extension=php_screw_plus.so > /usr/local/etc/php/conf.d/docker-php-ext-screw-plus.ini; \
    \
    rm -rf /usr/local/src/screw-plus;


#########################################
#                 配置                  #
#########################################
RUN set -eux; \
    \
    # 重设 www-data 用户和组的 UID 和 GID， 并设置 /var/www 目录的权限
    groupmod -g 1000 www-data; \
    usermod -u 1000 www-data; \
    chown -R www-data:www-data /var/www; \
    # 写入及修改配置文件
    { \
        echo 'always_populate_raw_post_data = -1'; \
        echo 'max_execution_time = 240'; \
        echo 'max_input_vars = 1500'; \
        echo 'upload_max_filesize = 32M'; \
        echo 'post_max_size = 32M'; \
        echo 'output_buffering = 4096'; \
        echo 'error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT'; \
        echo 'cgi.fix_pathinfo = 0'; \
    } | tee /usr/local/etc/php/conf.d/docker.ini; \
    # 写入 OPCache 配置
    { \
        echo 'opcache.enable = 1'; \
        echo 'opcache.memory_consumption = 256'; \
        echo 'opcache.interned_strings_buffer = 64'; \
        echo 'opcache.max_accelerated_files = 65407'; \
        echo 'opcache.validate_timestamps = 1'; \
        echo 'opcache.revalidate_freq = 300'; \
        echo 'opcache.save_comments = 1'; \
        echo 'opcache.fast_shutdown = 0'; \
    } | tee /usr/local/etc/php/conf.d/opcache.ini; \
    \
    # 写入示例 PHP 代码
    { \
        echo '<?php'; \
        echo 'phpinfo();'; \
    } | tee /var/www/html/index.php; \
    \
    # 清理临时文件
    rm -rf -rf /var/lib/apt/lists/*; \
    rm -rf /usr/local/src/*; \
#    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $NGINX_PHP_DEPS; \
    rm -rf /tmp/pear;


# 写入 Nginx 配置文件及启动 脚本
COPY conf/nginx.conf /usr/local/nginx/conf/nginx.conf
COPY conf/default.conf /usr/local/nginx/conf/vhosts/default.conf
COPY conf/nginx /etc/init.d/nginx
# composer 经常下载失败，所以直接换成预先下载好的版本
COPY vendors/composer.phar /usr/local/bin/composer


# 启动 Nginx
RUN set -eux; \
    \
    chmod +x /usr/local/bin/composer; \
    chmod a+x /etc/init.d/nginx; \
    update-rc.d -f nginx defaults; \
    chown -R www-data:www-data /usr/local/lib/php/extensions; \
    \
    # 写入启动脚本
    { \
        echo '#! /bin/sh'; \
        echo ; \
        echo 'set -eux;'; \
        echo ; \
        echo '/usr/local/nginx/sbin/nginx'; \
        echo 'echo "Nginx is started"'; \
        echo ; \
        echo 'php-fpm'; \
    } | tee /usr/local/bin/start.sh; \
    chmod +x /usr/local/bin/start.sh;


EXPOSE 80
EXPOSE 443

# 继承父镜像的 WORKDIR
#WORKDIR /var/www/html

CMD ["/usr/local/bin/start.sh"]
