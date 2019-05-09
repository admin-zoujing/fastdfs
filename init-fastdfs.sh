#!/bin/bash
#centos7.4安装fastdfs
chmod 777 -R /usr/local/src/fastdfs
cd /usr/local/src/fastdfs/rpm
rpm -ivh /usr/local/src/fastdfs/rpm/*.rpm --force --nodeps

#1、安装开发环境
 #yum -y groupinstall "Development Tools" "Server platform Development"
#2、安装libfastcommon
 cp -r /usr/local/src/fastdfs/libfastcommon /usr/local/
 #git clone https://github.com/happyfish100/libfastcommon.git
 cd /usr/local/libfastcommon/
 ./make.sh 
 ./make.sh install
#3、安装fastdfs
 cp -r /usr/local/src/fastdfs/fastdfs /usr/local/
 #git clone https://github.com/happyfish100/fastdfs.git
 cd /usr/local/fastdfs/
 ./make.sh 
 ./make.sh install
#tracker 配置：根据需求修改
 cd /etc/fdfs
 cp tracker.conf.sample tracker.conf
 mkdir -pv /data/fdfs/tracker
 sed -i 's|store_group=.*|store_group=group1|' /etc/fdfs/tracker.conf 
 sed -i 's|base_path=.*|base_path=/data/fdfs/tracker|' /etc/fdfs/tracker.conf 
 sed -i 's|http.server_port=.*|http.server_port=80|' /etc/fdfs/tracker.conf 
#添加systemd的units文件
cat > /usr/lib/systemd/system/fdfs_trackerd <<EOF
[Unit]
Description=FastDFS tracker script
After=syslog.target network.target

[Service]
Type=notify
ExecStart=/usr/bin/fdfs_trackerd /etc/fdfs/tracker.conf
ExecStop=/etc/init.d/fdfs_trackerd stop
ExecRestart=/etc/init.d/fdfs_trackerd restart

[Install]
WantedBy=multi-user.target
EOF

#通过systemd启动
 chmod +x /usr/lib/systemd/system/fdfs_trackerd.service
 systemctl daemon-reload 
 systemctl enable fdfs_trackerd.service 
 systemctl start fdfs_trackerd.service
 ss -tnl|grep 22122

#storage 配置根据需求修改
 cd /etc/fdfs
 cp storage.conf.sample storage.conf
 mkdir -pv /data/fdfs/storage/{m0,m1} 
 sed -i 's|base_path=.*|base_path=/data/fdfs/storage|' /etc/fdfs/storage.conf
 sed -i 's|store_path0=.*|store_path0=/data/fdfs/storage|' /etc/fdfs/storage.conf
 sed -i "s|tracker_server=.*|tracker_server=`ifconfig|grep 'inet'|head -1|awk '{print $2}'|cut -d: -f2`:22122|" /etc/fdfs/storage.conf

#添加systemd的units文件
 cat > /usr/lib/systemd/system/fdfs_storaged <<EOF
 [Unit]
 Description=FastDFS storage script
 After=syslog.target network.target

 [Service]
 Type=notify
 ExecStart=/usr/bin/fdfs_storaged /etc/fdfs/storage.conf
 ExecStop=/etc/init.d/fdfs_storaged stop
 ExecRestart=/etc/init.d/fdfs_storaged restart

 [Install]
 WantedBy=multi-user.target
EOF
#通过systemd启动
 chmod +x /usr/lib/systemd/system/fdfs_storaged.service
 systemctl daemon-reload 
 systemctl enablefdfs_storaged.service
 systemctl start fdfs_storaged.service
 ss -tnl|grep 23000
   
#client配置修改客户端配置文件
 cd /etc/fdfs
 cp client.conf.sample client.conf
 sed -i 's|base_path=.*|base_path=/data/fdfs/tracker|' /etc/fdfs/client.conf
 sed -i "s|tracker_server=.*|tracker_server=`ifconfig|grep 'inet'|head -1|awk '{print $2}'|cut -d: -f2`:22122|" /etc/fdfs/client.conf


#配置nginx为storage server提供http访问接口
#1、下载fastdfs-nginx-module
 cp -r /usr/local/src/fastdfs/fastdfs-nginx-module /usr/local/
 #git clone https://github.com/happyfish100/fastdfs-nginx-module.git
#2、下载nginx源码，并编译支持fastdfs
 #yum -y install pcre pcre-devel zlib openssl openssl-devel gcc 
 #wget http://nginx.org/download/nginx-1.12.2.tar.gz 
 cp -r /usr/local/src/fastdfs/nginx-1.12.2.tar.gz /usr/local/
 cd /usr/local/
 tar -zxvf nginx-1.12.2.tar.gz 
 cd nginx-1.12.2/
 useradd nginx -s /sbin/nologin
 mkdir -pv /usr/local/nginx/logs
 ./configure --prefix=/usr/local/nginx --lock-path=/usr/local/nginx/logs/nginx.lock --user=nginx --group=nginx --with-http_ssl_module --with-http_stub_status_module --with-pcre --add-module=../fastdfs-nginx-module/src
 make
 make install
#3、复制配置文件
 cp /usr/local/fastdfs-nginx-module/src/mod_fastdfs.conf  /etc/fdfs/
 cp /usr/local/fastdfs/conf/{http.conf,mime.types}  /etc/fdfs/
#4、配置fastdfs-nginx-module配置文件
 sed -i 's|base_path=.*|base_path=/data/fdfs/storage|' /etc/fdfs/mod_fastdfs.conf
 sed -i "s|tracker_server=.*|tracker_server=`ifconfig|grep 'inet'|head -1|awk '{print $2}'|cut -d: -f2`:22122|" /etc/fdfs/mod_fastdfs.conf
 sed -i 's|storage_server_port=.*|storage_server_port=23000|' /etc/fdfs/mod_fastdfs.conf
 sed -i 's|group_name=.*|group_name=group1|' /etc/fdfs/mod_fastdfs.conf
 sed -i 's|url_have_group_name =.*|url_have_group_name = true|' /etc/fdfs/mod_fastdfs.conf
 sed -i 's|store_path0=.*|store_path0=/data/fdfs/storage|' /etc/fdfs/mod_fastdfs.conf

 sed -i 's|http.anti_steal.token_check_fail=.*|http.anti_steal.token_check_fail=/usr/local/fastdfs/conf/anti-steal.jpg|' /etc/fdfs/http.conf

#cat >> /etc/fdfs/mod_fastdfs.conf <<EOF
#[group1]
#group_name=group1
#storage_server_port=23000
#store_path_count=1
#store_path0=/data/fdfs/storage
#EOF
#5、配置nginx
 #sed -i 's|listen       80;|listen       8080;|' /usr/local/nginx/conf/nginx.conf
 sed -i '56a\        location ~/group([0-9])/M00 {' /usr/local/nginx/conf/nginx.conf
 sed -i '57a\            root /data/fdfs/storage/data;' /usr/local/nginx/conf/nginx.conf
 sed -i '58a\            ngx_fastdfs_module;' /usr/local/nginx/conf/nginx.conf
 sed -i '59a\        }' /usr/local/nginx/conf/nginx.conf
      
cat >> /etc/profile.d/nginx.sh <<EOF
export PATH=$PATH:/usr/local/nginx/sbin
EOF
  source /etc/profile.d/nginx.sh
#6、为存储文件路径穿件链接至M00
  ln -sv /data/fdfs/storage/data  /data/fdfs/storage/data/M00 
#7、启动nginx和重启storage并上传文件测试
#服务随机启动
cat > /usr/lib/systemd/system/nginx.service <<EOF
[Unit]
Description=nginx 
After=network.target 

[Service]
Type=forking 
ExecStart=/usr/local/nginx/sbin/nginx 
ExecReload=/usr/local/nginx/sbin/nginx -s reload 
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

chmod +x /usr/lib/systemd/system/nginx.service
systemctl daemon-reload 
systemctl enable nginx.service 
systemctl stop nginx.service　
systemctl start nginx.service　
sed -i '26c \    server_tokens  off;' /usr/local/nginx/conf/nginx.conf
 nginx -t
 nginx 
 nginx -s reload
 /etc/init.d/fdfs_storaged restart
 ss -tnl|grep -E "(80|23000)"
 sleep 20
#上传文件
fdfs_upload_file /etc/fdfs/client.conf /usr/share/wallpapers/CentOS7/contents/images/2560x1600.jpg

rm -rf /usr/local/src/fastdfs




