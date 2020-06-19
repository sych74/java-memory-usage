#!/bash/sh 

function run {
	echo "***************************************************"
	host=$(hostname)
	echo $host
	os=$(cat /etc/*-release)
	echo $os
	mem=$(free -m)
	#checking output format as different versions of "free" may provide different output 
	[[ "$mem" == *"-/+"* ]] && {
		mem=$(free -mo)
	}
	echo $mem

	mtotal=$(echo $mem | cut -d' ' -f8)
	mused=$(echo $mem | cut -d' ' -f9)
	mfree=$(echo $mem | cut -d' ' -f10)
	mshared=$(echo $mem | cut -d' ' -f11)
	mbuff=$(echo $mem | cut -d' ' -f12)
	mavail=$(echo $mem | cut -d' ' -f13)
	swtotal=$(echo $mem | cut -d' ' -f15)
	swused=$(echo $mem | cut -d' ' -f16)
	swfree=$(echo $mem | cut -d' ' -f17)
	swshared=$(echo $mem | cut -d' ' -f18)
	swbuff=$(echo $mem | cut -d' ' -f19)
	swavail=$(echo $mem | cut -d' ' -f20)
	docker=$(docker -v)
	port=10239
	curl -Lo /tmp/jattach https://github.com/apangin/jattach/releases/download/v1.5/jattach
	chmod +x /tmp/jattach
	jattach="/tmp/jattach"
	curl -Lo /tmp/app.jar https://github.com/siruslan/java-memory-usage/raw/master/MemoryUsageCollector.jar
	jar=/tmp/app.jar

	for pid in $(pgrep -l java | awk '{print $1}'); do
		echo "-------------- $pid --------------"
		echo "$jattach $pid jcmd VM.version"
		java=$($jattach $pid jcmd VM.version | grep -v "Connected to remote JVM" | grep -v "Response code = 0")
		if [ $? -ne 0 ]; then
			java=$(java -version 2>&1)	
		fi
		echo $java

		if [[ "$java" == *"JDK 7."* || "$java" == *"1.7."* ]]; then
			echo "ERROR: Java 7 is not supported"
		else
			echo "$jattach $pid jcmd VM.flags"
			flags=$($jattach $pid jcmd VM.flags | grep -v "Connected to remote JVM" | grep -v "Response code = 0")
			echo $flags

			s=":InitialHeapSize="
			initheap=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))
			s=":MaxHeapSize="
			maxheap=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))
			s=":MaxNewSize="
			maxnew=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))
			s=":MinHeapDeltaBytes="
			minheapdelta=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))
			s=":NewSize="
			new=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))
			s=":OldSize="
			old=$(toMB $(echo ${flags#*$s} | cut -d' ' -f1))

			start="ManagementAgent.start jmxremote.port=$port jmxremote.rmi.port=$port jmxremote.ssl=false jmxremote.authenticate=false"
			echo "$jattach $pid jcmd \"$start\""
			resp=$($jattach $pid jcmd "$start" 2>&1)
			result=$?
			echo $resp
			if [ $result -eq 0 ]; then
				echo "java -jar $jar 2>&1"
				resp=$(java -jar $jar 2>&1)
				result=$?
				echo $resp

				if [ $(which docker) ]; then
					echo "Collecting info about docker container limits..."
					ctid=$(getCtInfo $pid id)
					st=$(docker stats $ctid --no-stream --format "{{.MemUsage}}")
					dckrused=$(echo $st | cut -d'/' -f1 | tr -s " " | xargs)
					dckrlimit=$(echo $st | cut -d'/' -f2 | tr -s " " | xargs)

					if [[ "$resp" == *"Failed to retrieve RMIServer stub"* ]]; then
						ip=$(getCtInfo $pid)	
						echo "java -jar $jar -h=$ip"
						resp=$(java -jar $jar -h=$ip)
						result=$?
						echo $resp
					fi
		            #If previous attempts failed then execute java -jar app.jar inside docker cotainer 
		            if [ $result -ne 0 ]; then
		            	ctid=$(getCtInfo $pid id)
		            	docker cp $jar $ctid:$jar
		            	resp=$(docker exec $ctid java -jar $jar) 
		            	result=$?
		            	docker exec $ctid rm -rf $jar 
		            	echo $resp
		            fi
		        fi

		        opts=$(echo $resp | cut -d'|' -f1)
		        if [ $result -eq 0 ]; then
		        	xms=$(echo $resp | cut -d'|' -f2)
		        	used=$(echo $resp | cut -d'|' -f3)
		        	committed=$(echo $resp | cut -d'|' -f4)
		        	xmx=$(echo $resp | cut -d'|' -f5)
		        	nhinit=$(echo $resp | cut -d'|' -f6)
		        	nhused=$(echo $resp | cut -d'|' -f7)
		        	nhcommitted=$(echo $resp | cut -d'|' -f8)
		        	nhmax=$(echo $resp | cut -d'|' -f9)
		        	gc=$(echo $resp | cut -d'|' -f10)
		        	nativemem=$(echo $resp | cut -d'|' -f11)
		        fi
		        echo "$jattach $pid jcmd ManagementAgent.stop"
		        $jattach $pid jcmd ManagementAgent.stop
		        echo "Done"
		    else
		    	opts="$resp"
		    	echo "ERROR: can't enable JMX for pid=$pid"
		    fi
		fi
		
		curl -fsSL -d "callback=response&action=insert&host=$host&os=$os&pid=$pid&mtotal=$mtotal&mused=$mused&mfree=$mfree&mshared=$mshared&mbuff=$mbuff&mavail=$mavail&swtotal=$swtotal&swused=$swused&swfree=$swfree&swshared=$swshared&swbuff=$swbuff&swavail=$swavail&java=$java&opts=$opts&gc=$gc&xmx=$xmx&committed=$committed&used=$used&xms=$xms&nhmax=$nhmax&nhcommitted=$nhcommitted&nhused=$nhused&nhinit=$nhinit&nativemem=$nativemem&flags=$flags&initheap=$initheap&maxheap=$maxheap&minheapdelta=$minheapdelta&maxnew=$maxnew&new=$new&old=$old&docker=$docker&dckrused=$dckrused&dckrlimit=$dckrlimit" -X POST "https://script.google.com/macros/s/AKfycbzs2J6KLEdAzxvi3vSnSipVG1EYGP5qaUvoRa_MAtv7LXPpgGU/exec"
	done
	rm -rf $jar $jattach
}

function getCtInfo {
	local pid="$1"

	if [[ -z "$pid" ]]; then
		echo "Missing host PID argument."
		exit 1
	fi

	if [ "$pid" -eq "1" ]; then
		echo "Unable to resolve host PID to a container name."
		exit 2
	fi

  #ps returns values potentially padded with spaces, so we pass them as they are without quoting.
  local parentPid="$(ps -o ppid= -p $pid)"
  local ct="$(ps -o args= -f -p $parentPid | grep containerd-shim)"
  m="moby/"
  if [[ -n "$ct" ]]; then
  	local ctid=$(echo ${ct#*$m} | cut -d' ' -f1)
  	if [ "$2" == "id" ]; then
  		echo $ctid
  	else
  		docker inspect $ctid | grep IPAddress | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
  	fi
  else
  	getCtInfo "$parentPid" $2
  fi
}

function toMB {
	local mb=1048576
	local value=$1

	if echo "$value" | grep -qE '^[0-9]+$' ; then
		echo $(($value/$mb))
	else
		echo ""
	fi	
}

run
