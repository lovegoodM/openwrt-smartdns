#!/bin/sh

file_md5="254e3cb757066890719c121fc9f83166"
exec_file_path="/etc/smartdns/domain/domain2ip.sh"
domain_file_path="/etc/smartdns/domain/domain.txt"
out_file_path="/etc/smartdns/custom.conf"

[ ! -f "$exec_file_path" ] && echo "不存在domain2ip.sh脚本" && exit 1
[ -z "$(md5sum "$exec_file_path" | grep "$file_md5")" ] && echo "不是一个正确的domain2ip.sh脚本" && exit 1

while read -r line; do
	if [ "$line" != "" ]; then
		sh $exec_file_path $line -o $out_file_path
	fi
done <$domain_file_path
exit 0
