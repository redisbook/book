#AOF


aof 原理有点类似 redo log。每次执行命令后如果数据发生了变化（server.dirty发生了变化），会接着调用 feedAppendOnlyFile。

    void call(RedisClient *c, struct RedisCommand *cmd) {
        long long dirty;
        dirty = server.dirty;
        cmd->proc(c);        //执行命令
        dirty = server.dirty-dirty;
        if (server.appendonly && dirty)
        feedAppendOnlyFile(cmd,c->db->id,c->argv,c->argc);

feedAppendOnlyFile并非把直接存入 aof 文件，而是先把命令存储到 server.aofbuf 里。 

    void feedAppendOnlyFile(struct RedisCommand *cmd, int dictid, robj **argv, int argc) { 
       
        buf = catAppendOnlyGenericCommand(buf,argc,argv);
        server.aofbuf = sdscatlen(server.aofbuf,buf,sdslen(buf));
        .... 
       if (server.bgrewritechildpid != -1) 
            server.bgrewritebuf = sdscatlen(server.bgrewritebuf,buf,sdslen(buf)); 
    }

在这个过程中，如果存在 bgrewritechild 进程，变化数据还会写到 server.bgrewritebuf 里。

待到接下来的循环的 before_sleep 函数会通过 flushAppendOnlyFile 函数把 server.aofbuf 里的数据 write 到 append file 里。

    void flushAppendOnlyFile(void) { 
        ....
        nwritten = write(server.appendfd,server.aofbuf,sdslen(server.aofbuf));
    
redis.conf里配置每次 write 到 append file 后，fsync的规则，fsync的作用大家都知道，把从page cache刷新到disk。

    #appendfsync always
    appendfsync everysec
    #appendfsync no

该参数的原理 MySQL 的 innodb_flush_log_at_trx_commit 一样，是个较影响io的一个参数，需要在高性能和不丢数据之间做 trade-off。软件的优化就是 trade-off的过程，没有银弹，默认选用的是 everysec，每次 fsync 会记录时间，距离上次 fsync 超过1s，则会再次触发fsync。

    /* Fsync if needed */ 
    now = time(NULL); 
    if (server.appendfsync == APPENDFSYNC_ALWAYS || 
        (server.appendfsync == APPENDFSYNC_EVERYSEC && 
         now-server.lastfsync > 1)) 
    {
        /* aof_fsync is defined as fdatasync() for Linux in order to avoid 
         * flushing metadata. */ 
        aof_fsync(server.appendfd); /* Let's try to get this data on the disk */ 
        server.lastfsync = now; 
    }

Redis.conf里的no-appendfsync-on-rewrite参数的意义是，如果在做rdb或者bgrewrite过程中，不会对aof文件进行fsync，这样对磁盘的写入操作不会因为要写 rdb 和 aof 两个文件而快速的摆动磁头，减少了寻道时间，让rdb、bgrewrite可以快速的完成，但这样同时增加了风险，因为生成rdb的时间还是比较长的。如果在这过程中os crash，部分aof数据还在page cache里，但还未写入到disk上。

    if (server.no_appendfsync_on_rewrite && 
        (server.bgrewritechildpid != -1 || server.bgsavechildpid != -1)) 
            return;      //跳出这个函数，不再进行fsync

另外为什么Redis采用这种模式，每次写完内存，再写到server.aofbuf，而不是直接写到aof文件内，这是一个很多很大的性能优化，因为一次循环可能接收多次网络请求，所以的变化都合并到aofbuf里，然后再写入文件里，把多次的小io，转化成一次连续的大io，这也是常规的数据库优化方法。

那么既然先写到server.aofbuf，写入aof文件之前，Redis crash会不会丢数据呢？答案是不会，为何？我先看看网络事件库如何处理读写事件

    if (fe->mask & mask & AE_READABLE) { 
        rfired = 1; 
        fe->rfileProc(eventLoop,fd,fe->clientData,mask); 
    }
    if (fe->mask & mask & AE_WRITABLE) { 
        if(!rfired||fe->wfileProc!=fe->rfileProc)
        fe->wfileProc(eventLoop,fd,fe->clientData,mask); 
    }

rfired变量决定了在同一次文件事件循环内，如果对于某个fd触发了可读事件的函数，不会再次触发写事件。我们来看函数执行的简化步骤：
* readQueryFromClient()
* call()
* feedAppendOnlyFile()
* 因为rfired原因退出本次循环 下一次循环
* beforeSleep()-->flushAppendOnlyFile()
* aeMain()--->sendReplyToClient()

只有执行完了flush之后才会通知客户端数据写成功了，所以如果在feed和flush之间crash，客户接会因为进程退出接受到一个fin包，也就是一个错误的返回，所以数据并没有丢，只是执行出了错。

Redis crash后，重启除了利用 rdb 重新载入数据外，还会读取append file(Redis.c 1561)加载镜像之后的数据。


##如何激活aof


激活aof，可以在Redis.conf配置文件里设置

    appendonly yes

也可以通过config命令在运行态启动aof

    cofig set appendonly yes

每次激活 aof ，调用函数 startAppendOnly(aof.c)必然的做执行一次 bgrewriteaof ，生成一个 aof 文件，并强制刷 fsync。这样做保证了aof文件在任何时候数据都是完整的。

    int startAppendOnly(void) { 
        ....
        if (rewriteAppendOnlyFileBackground() == REDIS_ERR) {
        ....

一旦开启 aof，则 Redis 重启后只会读取 aof 文件(Redis.c)，而无视rdb文件的存在。

Redis关闭（Redis.c）之时也会强制的刷一次fsync。

    int prepareForShutdown() { 
        ....
        if (server.appendonly) { 
            /* Append only file: fsync() the AOF and exit */ 
            aof_fsync(server.appendfd); 
        ....        

##bgrewriteaof


aof 的一个问题就是随着时间 append file 会变的很大，比如一个做 incr 的 key，aof 文件里记录的都是从1到N的自增的过程，其实我们只要保存最后的值即可。

所以我们需要 bgrewriteaof 命令重新整理文件，只保留最新的key-value数据，会调用 rewriteAppendOnlyFile 这个函数,该函数与 rdbSave 工作原理类似。保存全库的kv数据，但aof数据未压缩，而且是明文存储。

    int rewriteAppendOnlyFile(char *filename) { 
        snprintf(tmpfile,256,"temp-rewriteaof-%d.aof", (int) getpid()); 
        fp = fopen(tmpfile,"w"); 
        for (j = 0; j < server.dbnum; j++) { 
            if (o->type == REDIS_STRING) {
                //set
            } else if (o->type == REDIS_LIST) {
                //rpush
            } else if (o->type == REDIS_SET) {
                //sadd
            } else if (o->type == REDIS_ZSET) { 
                //zadd
            } else if (o->type == REDIS_HASH) { 
                //hset
            } 

等 bgrewritecihld 进程完成快照退出之时(Redis.c)，再调用 backgroundRewriteDoneHandler 函数

    if ((pid = wait3(&statloc,WNOHANG,NULL)) != 0) { 
        if (pid == server.bgsavechildpid) { 
            backgroundSaveDoneHandler(statloc); 
        } else {                          
            backgroundRewriteDoneHandler(statloc); 
        }

backgroundRewriteDoneHandler 处理 bgrewriteaof 生成的临时文件，合并 bgrewritebuf 和临时文件两部分数据后，就生成了新的 aof 文件，并做一次强制的 fsync。

    void backgroundRewriteDoneHandler(int statloc) { 
        .... 
        fd = open(tmpfile,O_WRONLY|O_APPEND);
        .... 
        write(fd,server.bgrewritebuf,sdslen(server.bgrewritebuf)
        .... 
        rename(tmpfile,server.appendfilename)
        .... 
        if (server.appendfsync != APPENDFSYNC_NO) aof_fsync(fd)
        ...

合并 bgrewritebuf 很重要，否则最终的 aof 文件里的数据和内存里的数据就不一致了。

##aof文件格式


我们来看看aof文件的格式，知道aof的格式可以很方便解析他，可以自己实现更加异步的（Redis的复制已经是异步模式了）的复制技术。aof文件是ascii格式的，意味着可以明文的读取，而rdb文件可能是经过压缩的，所以即便aof文件做过 bgrewriteaof，aof 文件也是远大于rdb 文件。

    *参数的个数\r\n
    $参数1的长度\r\n
    参数1\r\n
    …
    $参数N的长度\r\n
    参数N\r\n

例如一个 "set a 1" 的命令放到aof文件里的格式就是这样的。

    *3^M
    $3^M
    set^M
    $1^M
    a^M
    $1^M
    1^M

执行命令前后，server.dirty 发生变化的命令，才会存储到 aof 文件里。

如果出现事务，多个命令会在exec后出现在aof文件里，例如一个mulit，set a 1, set b 2，exec命令之后的文件格式如下。

    *1^M 
    $5^M 
    MULTI^M 
    *3^M 
    $3^M 
    set^M 
    $1^M 
    a^M 
    $1^M 
    1^M 
    *3^M 
    $3^M 
    set^M 
    $1^M 
    b^M 
    $1^M 
    2^M 
    *1^M 
    $4^M 
    exec^M 

Redis-check-aof 这个 binary 可以用来检测 aof 文件的合法性。原理简单，先读取×后的数字，确定参数格式，再读取$后参数的长度，再读取参数。对于事务需要额外的处理，出现multi的地方必须要出现exec。

当Redis出现crash，Redis重启的时候（Redis.c），如果激活了aof，则会查找aof文件，并载入这个aof文件。

    if (server.appendonly) { 
        if (loadAppendOnlyFile(server.appendfilename) == REDIS_OK) 
            RedisLog(REDIS_NOTICE,"DB loaded from append only file: %ld seconds",time(NULL)-start); 
    } else {
        if (rdbLoad(server.dbfilename) == REDIS_OK) 
            RedisLog(REDIS_NOTICE,"DB loaded from disk: %ld seconds",time(NULL)-start); 
    }

载入 aof 文件的方法很有意思，先是创建一个 fake client ，这个 client 并非通过网络连接上来的客户端，而是伪造的一个对象，把 aof 文件里的命令一一保存在 client 的 arc，argv 里，使得这 client 像是某个网络连接连接上来，发送消息给服务端一样，这样处理 aof 里命令的方法就可以重用，而不需要额外的编写程序了。

    int loadAppendOnlyFile(char *filename) { 
        .... 
        fakeClient = createFakeClient(); 
        while(1) {
            fgets(buf,sizeof(buf),fp)
            argc = atoi(buf+1);     //命令参数格式
            argv = zmalloc(sizeof(robj*)*argc);
            for (j = 0; j < argc; j++) { 
               .... 
            }
            cmd = lookupCommand(argv[0]->ptr); 
            fakeClient->argc = argc; 
            fakeClient->argv = argv; 
            cmd->proc(fakeClient);    //模拟客户端执行命令
            .... 
        }
        freeFakeClient(fakeClient);
        ...
    }

