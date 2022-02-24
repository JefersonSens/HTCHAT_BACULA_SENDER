######################################################################################
#!/bin/bash
# /etc/bacula/scripts/_send_whatsapp.sh

# Transforma bytes em MB/KB/TB/PB/EB/ZB/YZ
b2h(){
    SLIST=" bytes, KB, MB, GB, TB, PB, EB, ZB, YB"
    POWER=1
    VAL=$( echo "scale=2; $1 / 1" | bc)
    VINT=$( echo $VAL / 1024 | bc )
    while [ ! $VINT = "0" ]
    do
        let POWER=POWER+1
        VAL=$( echo "scale=2; $VAL / 1024" | bc)
        VINT=$( echo $VAL / 1024 | bc )
    done
    echo $VAL$( echo $SLIST  | cut -f$POWER -d, )
}


# Variaveis
RECIPIENT_NUMBER=""
LOG="/etc/bacula/log/whatsapp.log"
GROUP="false"
SENDER="BACULA"
TOKEN=""
API=""

if [ $GROUP = "true" ] ; then
   ZAP="g.us"
else
   ZAP="s.whatsapp.net"
fi


# PGSQL config
DBUSER="bacula"
DBPASSWORD=""
DBNAME="bacula"

# query do pgsql
sql_query="select Job.Name, Job.JobId,(select Client.Name from Client where Client.ClientId = Job.ClientId) as Client, Job.JobBytes, Job.JobFiles,
case when Job.Level = 'F' then 'Full' when Job.Level = 'I' then 'Incremental' when Job.Level = 'D' then 'Differential' end as Level,
(select Pool.Name from Pool where Pool.PoolId = Job.PoolId) as Pool,
(select Storage.Name  from JobMedia left join Media on (Media.MediaId = JobMedia.MediaId) left join Storage on (Media.StorageId = Storage.StorageId)
where JobMedia.JobId = Job.JobId limit 1 ) as Storage, date_format( Job.StartTime , '%d/%m/%Y %H:%i:%s' ) as StartTime, date_format( Job.EndTime , '%d/%m/%Y %H:%i:%s' ) as EndTime,
sec_to_time(TIMESTAMPDIFF(SECOND,Job.StartTime,Job.EndTime)) as Duration, Job.JobStatus, 
(select Status.JobStatusLong from Status where Job.JobStatus = Status.JobStatus) as JobStatusLong
from Job where Job.JobId=$1"

# Pegando os campos da string gerada pela query
str=`echo -e "$sql_query" | mysql -u $DBUSER -p$DBPASSWORD -D $DBNAME -B |  while read; do sed 's/t/|/g'; done`
JobName=`echo $str | cut -d" " -f1`
JobId=`echo $str | cut -d" " -f2`
Client=`echo $str | cut -d" " -f3`
JobBytes=`b2h $(echo $str | cut -d" " -f4)`
JobFiles=`echo $str | cut -d" " -f5`
Level=`echo $str | cut -d" " -f6`
Pool=`echo $str | cut -d" " -f7`
Storage=`echo $str | cut -d" " -f8`
StartDate=`echo $str | cut -d" " -f9`
StartTime=`echo $str | cut -d" " -f10`
EndDate=`echo $str | cut -d" " -f11`
EndTime=`echo $str | cut -d" " -f12`
StartFull="$StartDate $StartTime"
EndFull="$EndDate $EndTime"
Duration=`echo $str | cut -d" " -f13`
JobStatus=`echo $str | cut -d" " -f14`
Status=`echo $str | cut -d" " -f15`

# Emojis
# Certo
# http://emojipedia.org/white-heavy-check-mark/
# Errado
# http://emojipedia.org/cross-mark/

# Mudando o inicio da mensagen de acordo com o status do job
if [ "$JobStatus" = "T" ] ; then
echo sim
   HEADER="➡️ BACULA BAKUP ✅  ⬅️ "  # OK
   Response="✅"
else
   HEADER="➡️ BACULA BAKUP ❌  ⬅️ "  # Error
   Response="❌"
fi

# Formatando a mensagem
MESSAGE=". \\\n $HEADER \\\n JobName=$JobName \\\n Jobid=$JobId \\\n Client=$Client \\\n JobBytes=$JobBytes \\\n JobFiles=$JobFiles \\\n Level=$Level \\\n Pool=$Pool \\\n Storage=$Storage \\\n StartFull=$StartTime \\\n EndFull=$EndTime \\\n Duration=$Duration \\\n JobStatus=$Response \\\n Status=$Status"
MESSAGELOG="Message: JobName=$JobName | Jobid=$JobId | Client=$Client | JobBytes=$JobBytes | Level=$Level | Status=$Status"

# Tenta entregar a mensagem por no maximo 20 vezes
COUNT=1
while [ $COUNT -le 20 ]; do

   echo "$(date +%d/%m/%Y %H:%M:%S) - Start message send (attempt $COUNT) ..." >> $LOG
   echo "$(date +%d/%m/%Y %H:%M:%S) - $MESSAGELOG" >> $LOG

   while [ $(ps -ef | grep yowsup | grep -v grep | wc -l) -eq 1 ]; do
      echo "$(date +%d/%m/%Y %H:%M:%S) - Yowsup still running, waiting 2 seconds before a new try ..." >> $LOG
      sleep 2; 
   done;
curl -X POST -H "Content-Type:application/json" -H "token:$TOKEN"   -d "{\"query\":\"query partner_api_send_message{partner_api_send_message(recipient:\\\"$RECIPIENT_NUMBER@$ZAP\\\" message:\\\"$MESSAGE\\\" tipo:\\\"text\\\" sender_name:\\\"$SENDER\\\"){message}}\",\"variables\":{},\"operationName\":\"partner_api_send_message\"}" $API
   RET=$?

   if [ $RET -eq 0 ]; then
     echo "$(date +%d/%m/%Y %H:%M:%S) - Attempt $COUNT executed successfully!" >> $LOG 
     exit 0
   else
     echo "$(date +%d/%m/%Y %H:%M:%S) - Attempt $COUNT failed!" >> $LOG 
     echo "$(date +%d/%m/%Y %H:%M:%S) - Waiting 30 seconds before retry ..." >> $LOG
     sleep 30
     (( COUNT++ ))
   fi

done
######################################################################################
