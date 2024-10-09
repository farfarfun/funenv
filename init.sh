#!/bin/bash
root="/farfarfun"
download_if_not_exists() {
	local FILE_NAME="$1"
	local DOWNLOAD_URL="$2"
	if [ -f "$FILE_NAME" ]; then
		echo "文件 $FILE_NAME 已存在，跳过下载。"
	else
		echo "文件 $FILE_NAME 不存在，开始下载..."
		if ! wget -O "$FILE_NAME" "$DOWNLOAD_URL"; then
			echo "下载失败，请检查 URL 或网络连接。"
			return 1
		fi
		echo "文件 $FILE_NAME 下载完成。"
	fi
}
install_miniconda() {
	local FILE_NAME="$root/miniconda"
	if [ -d "$FILE_NAME" ]; then
	  echo "$FILE_NAME 已存在，跳过"
		return
	fi
	url="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
	local filename="$root/Miniconda3-latest-Linux-x86_64.sh"
	download_if_not_exists "$filename" "$url"
	sh $filename -b -f -p $root/miniconda
	rm $filename
}
init_env() {
	if [ -d "$root" ]; then
		echo "$root 已存在，跳过"
	else
		mkdir $root
	fi
	cd $root
	install_miniconda
}

init_env

#
#
## 定义文件名和下载链接
#FILE_NAME1="example1.txt"
#DOWNLOAD_URL1="http://example.com/path/to/example1.txt"
#
#FILE_NAME2="example2.txt"
#DOWNLOAD_URL2="http://example.com/path/to/example2.txt"
#
## 调用下载函数
#download_if_not_exists "$FILE_NAME1" "$DOWNLOAD_URL1"
#download_if_not_exists "$FILE_NAME2" "$DOWNLOAD_URL2"

