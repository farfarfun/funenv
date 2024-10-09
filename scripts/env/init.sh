# ssh-keygen -t rsa -C "niuliangtao@qq.com"
vim /etc/ssh/sshd_config

chown -R bingtao /home/bingtao
chmod 700 /home/bingtao
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
systemctl restart sshd.service
