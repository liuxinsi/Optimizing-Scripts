#!/bin/sh

# jre home
JRE_HOME=../jre

# max heap in mb
MAX_HEAP_SIZE=

#max meta space
MAX_META_SPACE_SIZE=

#young age 
HEAP_NEWSIZE=

# calculate heap sizes ,code ref.cassandra_env_script
calculate_heap_sizes()
{
    case "`uname`" in
        Linux)
            system_memory_in_mb=`free -m | awk '/:/ {print $2;exit}'`
            system_cpu_cores=`egrep -c 'processor([[:space:]]+):.*' /proc/cpuinfo`
        ;;
        FreeBSD)
            system_memory_in_bytes=`sysctl hw.physmem | awk '{print $2}'`
            system_memory_in_mb=`expr $system_memory_in_bytes / 1024 / 1024`
            system_cpu_cores=`sysctl hw.ncpu | awk '{print $2}'`
        ;;
        SunOS)
            system_memory_in_mb=`prtconf | awk '/Memory size:/ {print $3}'`
            system_cpu_cores=`psrinfo | wc -l`
        ;;
        Darwin)
            system_memory_in_bytes=`sysctl hw.memsize | awk '{print $2}'`
            system_memory_in_mb=`expr $system_memory_in_bytes / 1024 / 1024`
            system_cpu_cores=`sysctl hw.ncpu | awk '{print $2}'`
        ;;
        *)
            # assume reasonable defaults for e.g. a modern desktop or
            # cheap server
            system_memory_in_mb="2048"
            system_cpu_cores="2"
        ;;
    esac

    # some systems like the raspberry pi don't report cores, use at least 1
    if [ "$system_cpu_cores" -lt "1" ]
    then
        system_cpu_cores="1"
    fi

    # set max heap size based on the following
    # max(min(1/2 ram, 1024MB), min(1/4 ram, 8GB))
    # calculate 1/2 ram and cap to 1024MB
    # calculate 1/4 ram and cap to 8192MB
    # pick the max
    half_system_memory_in_mb=`expr $system_memory_in_mb / 2`
    quarter_system_memory_in_mb=`expr $half_system_memory_in_mb / 2`
    if [ "$half_system_memory_in_mb" -gt "1024" ]
    then
        half_system_memory_in_mb="1024"
    fi
    if [ "$quarter_system_memory_in_mb" -gt "8192" ]
    then
        quarter_system_memory_in_mb="8192"
    fi
    if [ "$half_system_memory_in_mb" -gt "$quarter_system_memory_in_mb" ]
    then
        max_heap_size_in_mb="$half_system_memory_in_mb"
    else
        max_heap_size_in_mb="$quarter_system_memory_in_mb"
    fi
    MAX_HEAP_SIZE="${max_heap_size_in_mb}M"

    # Young gen: min(max_sensible_per_modern_cpu_core * num_cores, 1/4 * heap size)
    max_sensible_yg_per_core_in_mb="100"
    max_sensible_yg_in_mb=`expr $max_sensible_yg_per_core_in_mb "*" $system_cpu_cores`

    desired_yg_in_mb=`expr $max_heap_size_in_mb / 4`

    if [ "$desired_yg_in_mb" -gt "$max_sensible_yg_in_mb" ]
    then
        HEAP_NEWSIZE="${max_sensible_yg_in_mb}M"
    else
        HEAP_NEWSIZE="${desired_yg_in_mb}M"
    fi
}

# get java version
if [  $JRE_HOME ];then
    echo "use jre_home:$JRE_HOME"
    java_ver_output=`"$JRE_HOME/bin/java" -version 2>&1`
else
    echo "use current env"
    java_ver_output=`"${JAVA:-java}" -version 2>&1`
fi

jvmver=`echo "$java_ver_output" | grep '[openjdk|java] version' | awk -F'"' 'NR==1 {print $2}' | cut -d\- -f1`
JVM_VERSION=${jvmver%_*}

# check java version
if [ "$JVM_VERSION" \< "1.8" ] ; then
    echo "current jdk version is $JVM_VERSION use jdk8 pls or specify JRE_HOME_PATH"
    exit 1;
fi


# check heap size
if [ ! $MAX_HEAP_SIZE ];then
    echo "calculate heap sizes"
    calculate_heap_sizes
    echo "current os had ${system_memory_in_mb}M ,calculated size:$MAX_HEAP_SIZE"
fi

# check meta space size
if [ ! $MAX_META_SPACE_SIZE ];then
    echo "meta space size not specified. use default size"
    MAX_META_SPACE_SIZE=256m
fi

# check new age
if [ ! $HEAP_NEWSIZE ];then
    echo "new age size not specified. use default size"
    HEAP_NEWSIZE=256m
fi



# tomcat settings
export JRE_HOME=$JRE_HOME
export CATALINA_PID=../tomcat.pid

export CATALINA_OPTS="-server -Xms$MAX_HEAP_SIZE -Xmx$MAX_HEAP_SIZE -Xmn${HEAP_NEWSIZE} -XX:MaxMetaspaceSize=$MAX_META_SPACE_SIZE -Xss512k -Xloggc:../logs/gc.log -XX:+PrintGCDetails -XX:+UseParallelGC -Xverify:none -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=../logs/crash.hprof"

exec ./startup.sh
