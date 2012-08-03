#主框架

![redis-server](/image/reds_server.png)

我们从redis-server启动说起，从main函数开始遍历一下各个关键函数，先了解redis主框架。
	    首先initServerConfig函数会设置一些默认的参数，比如监听端口为6379,默认的db个数为16等。PopulateCommandTable会把命令和函数数组转化成hash table结构，这个后面会详细描述。如果启动参数里有redis.conf，LoadServerConfig还会读入redis.conf里的参数，覆盖默认值。
		    initServer会给redisServer这个数据结构做初始化，申请各自成员的空间，有些是list结构，有些是dict结构。然后添加一个时间事件，函数是serverCron。这个函数会每100ms执行一次，后面会详细描述这个函数的作用。然后是启动监听，注册一个监听的文件事件，把accept行为注册到只读的监听文件描述符上。然后如果有激活aof功能，还会打开aof文件。接着会判断数据目录是否存在镜像文件或者aof文件，如果存在，redis会讲数据载入到内存中。然后进入主循环。


#文件事件, 时间事件

主循环主要处理刚才注册的时间事件和文件事件。如何保证时间事件每100ms执行一次，又能即时的处理网络交互的文件事件呢？
				    redis处理的比较巧妙。先执行aeSearchNearestTimer确定距离下次时间事件执行还有多少时间，假设第一次执行直到下次时间事件还有100ms，先执行文件事件，epool_wait的超时时间就设置为100ms，如果10ms后，有网络交互后经过一系列的处理后消耗20ms，该次循环结束。aeSearchNearestTimer会再次计算距离下次时间事件的间隔为100-10-20=70ms，于是epoll_wait的超时时间为70ms，70ms之内如果没有处理文件事件，则执行时间事件。这样即保证了即时处理文件事件，在文件事件处理完毕后又能按时处理时间事件。
					    时间事件serverCron会处理很多函数，例如定时打出日志展现redis目前的状况，查看是否需要rehash来迁移keys到新的bucket，这个后面会详细讲。关闭长时间不工作的client。处理bgsave或者bgrewriteaof的子进程退出后的收尾工作。判断有keys的变化而需要执行bgsave。清理expire的key。检测slave节点的状况，处理自己作为slave的连接master的工作。
