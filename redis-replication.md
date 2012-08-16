#复制

Redis的复制的原理和使用都非常简单。只需要在slave端键入

        slaveof masterip port

取消复制，从slave状态的转换回master状态，切断与原master的数据同步。

        slaveof no one

一个master可以有多个slave，不可以 dual master。

master 有变化的时候会主动的把命令传播给每个slave。slave同时可以作为其他的slave的master，前提条件是这个slave已经处于稳定状态（REDIS_REPL_CONNECTED）。

slave在复制的开始阶段处于阻塞状态（sync_readline）无法对外提供服务。


#复制部分源码分析


![replication](https://raw.github.com/redisbook/book/master/image/redis_replication.png)

slave 端接收到客户端的 "slaveof masterip port" 命令之后，调度 slaveofCommand 保存的 masterip、port，修改 server.replstate为 REDIS_REPL_CONNECT，然后返回给客户端 OK，复制的行为是异步的，返回给用户OK只是。

slave 端主线程在时间事件 serverConn（redis.c 518行）里执行replicationCron（redis.c 646行）开始与master的连接。syncWithMaster 函数与 master 的通信。经过校验之后（如果需要），会发送一个"SYNC" command 给 master 端，然后打开一个临时文件用于接收接下来master发过来的 rdb 文件数据。再添加一个文件事件注册 readSyncBulkPayload 函数，这个就是接下来用于接收rdb文件的数据的函数，然后修改状态为 REDIS_REPL_TRANSFER。

master 接收到 "SYNC" command 后，跳转到 syncCommand 函数（replication.c 556行）。syncCommand 会调度 rdbSaveBackground 函数，启动一个子进程做一个全库的快照，并把状态改为 REDIS_REPL_WAIT_BGSAVE_END。master 的主线程的 serverCron 会检查这个持久化的子进程是否退出。

    if ((pid = wait3(&statloc,WNOHANG,NULL)) != 0) {
        if (pid == server.bgsavechildpid) {
            backgroundSaveDoneHandler(statloc);
        } 

如果bgsave子进程正常退出，会调用backgroundSaveDoneHandler函数继续复制的工作，该函数打开刚刚产生的rdb文件。然后注册一个sendBulkToSlave函数用于发送rdb文件，状态切换至REDIS_REPL_SEND_BULK。sendBulkToSlave作用就是根据上面打开的rdb文件，读取并发送到slave端，当文件全部发送完毕之后修改状态为REDIS_REPL_ONLINE。

我们回到slave，上面讲到slave通过readSyncBulkPayload接收rdb数据，接收完整个rdb文件后，会清空整个数据库emptyDb()(replication.c 374)。然后就通过rdbLoad函数装载接收到的rdb文件，于是slave和master数据就一致了，然后把状态修改为REDIS_REPL_CONNECTED。
    接下来就是master和slave之间增量的传递的增量数据，另外slave和master在应用层有心跳检测（replication.c 543）和超时退出（replication.c 511）。

介绍一些replication相关的几个数据结构和状态。
slave端的server变量与复制相关的变量。

    struct redisServer{
        ...
        char *masterauth;    //主库的密码 
        char *masterhost;    //主库的ip
        int masterport;      //主库的port
        redisClient *master; //slave连到master的连接，由slave主动发起                                                       
        int replstate;       //slave端的状态
        off_t repl_transfer_left;  //从master读取.rdb，还需要读取多少字节，
                                   // 开始是-1,然后会获得一个.rdb的大小，每次读取部分.rdb部分后，这个值会递减

        int repl_transfer_s;       //slave连到master的fd
        int repl_transfer_fd;      //接收.rdb时，写入临时文件的fd
        char *repl_transfer_tmpfile;  //接收.rdb的临时文件名(temp-xxx.pid.rdb)
        time_t repl_transfer_lastio;  //最近一次读取的时间，防止超时 
        int repl_serve_stale_data;    //当slave与master的连接状态不正常（不是REDIS_REPL_CONNECTED状态）的时候，是否提供服务，还是只能使用info、slaveof命令。
        ...
    }

slave端的server->master

    redisClient {

        int flags;	//slave连接的是什么角色，这里是REDIS_MASTER

    }

服务端的redisClient的信息

    redisClient {
        int flags;     //slave连接上来的client，这里是REDIS_SLAVE
        int repldbfd;   //传送.rdb数据给slave的时候的fd
        int slaveseldb; //slave的当前db id
        int repldboff;  //传送.rdb数据给slave的偏移量，直到等于repldbsize才传送完毕
        int repldbsize; //.rdb文件的大小
        int replstate; //
    }

REDIS_CMD_FORCE_REPLICATION 哪些命令必须传输给 slave 端。



