
#  ps -ef | grep code
#curl -fsSL https://code-server.dev/install.sh | sh
nohup code-server --config configs/code-server.yaml  >>./logs/darkdev/darkdev-$(date +%Y-%m-%d).log 2>&1 &

#nohup natapp -authtoken=595b08267b73d098 >>logs/code-server/code-server-$(date +%Y-%m-%d).log 2>&1 &
#tail -f logs/code-server/code-server-$(date +%Y-%m-%d).log



