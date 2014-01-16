#!/bin/bash
#
#         服务器简单监测脚本
#
#				2014.01.09
#
#		Powered by nbsp@outlook.com
#
#
#	v1.0  2014.01.09 
#	通过简单的配置 monitor.conf文件的方式
#	就能添加需要检测的主机及其端口（格式参考实例）
#	完成了ping监控主机、nc监控端口两大功能
#	
#	v1.1 2014.01.10
#	增加ping不通或端口不通以及延时厉害监测并发邮件功能
#	增加端口以及ping检测能独立分开执行，通过配置文件约定写法实现
#	增加ping延时检测功能
#	增加日志文件压缩功能
#
#	v1.1.1 2014.01.12
#	解决cron调用mail生成附件问题，字符编码问题。改成英文即可！
#
#	v1.2 2014.01.12
#	增加邮件列表配置文件mail.conf,注释用#符号
#	将原端口分隔符"-" 改为"|"
#	IP配置文件的注释用"#"
#


#####################################################################################


#脚本根目录
base=/data4/monitor


#邮件接收列表
mail_list="$base"/mail.conf

#待检测ip配置文件
#如果没有参数传入就默认使用该配置文件
#配置文件格式入下
#  x.x.x.x 只ping地址
#  x.x.x.x:xx|xx ping地址以及检测端口
#  nx.x.x.x:xx|xx 只检测端口不ping地址
conf="$base"/monitor.conf

#脚本第一个参数（暂且支持一个参数）
param=$1

#ping最大延时毫秒
pingMax=200

#ping超时时间默认为一秒
pingTimeout=10

#ping计数默认为一次
pingNumber=3

#ping packetsize
pingSize=64

#nc端口检测超时时间默认为一秒
ncTimeout=3


#检测失败项目计数
checkFail=0

#检测成功项目计数
checkOk=0

#ping延时严重项目计数
checkOut=0

#成功日志变量
olog=''

#失败日志变量
flog=''

#延时日志
nlog=''

#日志文件
log="$base"/run.log

#日志压缩配置项

#日志压缩日期
cdate="01"

#压缩后文件名
clog="$log"`date +%Y%m`

#####################################################################################

#检测IP状态是否正常
ping_ip(){

ip=$1

n=$pingNumber

w=$pingTimeout

s=$pingSize


#ping -s $s -c $n -w $w $ip  >/dev/null 2>&1
avg=`ping -s $s -c $n -w $w $ip | grep avg | awk -F/ '{print $5}'`

if [ -z "$avg" ];then

	echo ping $ip Failed

	checkFail=`expr $checkFail + 1`
	nowtime=`date +%T" "%x`
	#flog=`echo [FAL] ping $ip failed `"\n$flog"
	flog=`echo [ FAL $nowtime ] ping $ip Failed `"\n$flog"

else
	if [[ "${avg%%.*}" -le "$pingMax" ]];then

		echo ping $ip avg "${avg}"ms

		checkOk=`expr $checkOk + 1`

		nowtime=`date +%T" "%x`
		
		olog=`echo [ OK $nowtime ] ping $ip \(avg=$avg\) succeed`"\n$olog"

	else
		echo "ping $ip avg $avg > $pingMax" 
			
		checkOut=`expr $checkOut + 1`

		nowtime=`date +%T" "%x`
        
	    	nlog=`echo [ WAR $nowtime ] ping $ip Delay $avg \> $pingMax`"\n$nlog"
	fi

fi

}

#检测端口是否正常
check_port(){

ip=$1

port=$2

w=$ncTimeout

#nc -w $w -vz $ip $port  >/dev/null 2>&1
nc -n -w $w -vz $ip $port

if [ "$?" -eq "0" ];then

	checkOk=`expr $checkOk + 1`

	nowtime=`date +%T" "%x`
        
	olog=`echo [ OK $nowtime ] $ip:$port connected`"\n$olog"

else

	checkFail=`expr $checkFail + 1`

	nowtime=`date +%T" "%x`
        
	#flog=`echo [FAL] $ip:$port disconnect`"\n$flog"
	flog=`echo [ FAL $nowtime ] $ip:$port Port Listener failed`"\n$flog"

fi

}

#解析配置文件
pase_conf(){

cnf=$1

while read line

do
	
if [ -n "$line" ];then

pase_line $line

fi

done < $cnf

}

#解析每一行
pase_line(){

line=$1

ip=`echo $line | awk -F: '{print $1}'`

port=`echo $line | awk -F: '{print $2}'`

ports=`echo $port | sed  "s/|/ /g"i`

if [ "${ip:0:1}" != "#" ];then

	if [ "${ip:0:1}" == "!" ];then

		ip=${ip:1}
	else
		ping_ip $ip
	fi

	for i in $ports ;do
	
		check_port $ip $i

	done
fi

}

#发送邮件函数
send_mail(){
	list=$1
	t=$2
	c=$3

while read i;do
	
if [ "${i:0:1}" != "#" ];then

	if [ -n "$i" ];then

		echo -e "$c" | mail -s "$t" "$i" && echo -e "[ MAL `date +%F` ] `date +%T` has been sent email to $i" >> $log

	fi

fi

done < $list

}

#日志压缩函数
compressLog(){

srcLog=$1

dstLog=$2

if [ -f "$srcLog" ];then

mv $srcLog $dstLog

gzip $dstLog

fi

}

#####################################################################################

init(){

#压缩日志
if [ "`date +%d`" == "$cdate" ];then
	
	if [ ! -f "${clog}.gz" ];then
	
		compressLog  "$log" "$clog"
	
	fi

fi

stime=`date  +%s`

if [ -n "$param" ];then

	pase_line $param
	
	exit

else

	echo "START    `date`" >> $log
	
	pase_conf $conf

fi

etime=`date  +%s`

rtime=`expr $etime -  $stime`

header="{ succeed : $checkOk , failed : $checkFail , timeout : $checkOut }"

#成功日志
echo -e `echo "$olog"` >> $log

if [ "$checkFail" -ne "0" ];then

#失败日志
echo -e `echo "$flog"` >> $log

fi

if [ "$checkOut" -ne "0" ];then 

#ping延时日志
echo -e `echo "$nlog"` >> $log

fi


echo -e "$header  runtime:$rtime\n"  >> $log


if [ "$checkFail" -ne "0" ];then

	send_mail "${mail_list}" "[ Monitor ] - Fail : ${header}" "Runtime ${rtime} s\n\n${flog}${nlog}"

else

	if [ "$checkOut" -ne "0"  ];then

		send_mail "${mail_list}" "[ Monitor ] - Warning : ${header}" "Runtime ${rtime} s\n\n${nlog}"

	fi
fi

echo "END    `date`" >> $log

echo "------------------------------------------------------------------------" >> $log

}

#启动程序
init
