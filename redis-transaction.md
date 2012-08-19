#事务


##multi commands

Redis 使用 multi、exec、discard 等命令实现简单事务，可以同时提交或者同时回滚，但不能处理部分的事务，事务过程中进程crash会导致部分数据写入Redis，而部分数据失败。实例重启并不会回滚本不该写入的数据。

不是传统意义上的事务，只是一次性执行多个语句，所以你无法读数据，也应用无法交互，你只能一股脑的写或者修改数据, 这个在 scripting 有所改观。

另外使用watch命令观察某些key，如果exec之前，这些key出现修改则回滚整个事务，否则提交事务，来达到乐观锁的作用。Watch配合setnx可以设计出媲美关系型数据库的分布式锁机制。

我们先来看multi，这个命令发送到服务端后，会修改 RedisClient 对象，把 client->flag 设置为 REDIS_MULTI。

        void multiCommand(RedisClient *c) { 
            if (c->flags & REDIS_MULTI) { 
                addReplyError(c,"MULTI calls can not be nested"); 
                return; 
            }
            c->flags |= REDIS_MULTI; 
            addReply(c,shared.ok); 
        }

从此之后，原本要执行的命令不再调用 call 函数，反而执行了 queueMultiCommand 函数，把命令保存到一个管道里。

        int processCommand(RedisClient *c) { 
            ...
            if (c->flags & REDIS_MULTI && 
                cmd->proc != execCommand && cmd->proc != discardCommand && 
                cmd->proc != multiCommand && cmd->proc != watchCommand) 
            { 
                queueMultiCommand(c,cmd);
                addReply(c,shared.queued);
            } else {
                if (server.vm_enabled && server.vm_max_threads > 0 && 
                    blockClientOnSwappedKeys(c,cmd)) return REDIS_ERR; 
                call(c,cmd); 
            }

queueMultiCommand 函数是将接下来的命令和参数塞入 RedisClient 对象的一个命令数组 mstate 里。命令都是数组的形式添加到command里，count表示命令的个数，扩展使用的是realloc整个数组。

![multi commands](https://raw.github.com/redisbook/book/master/image/redis_multi_command.png)

当需要回滚的时候我们键入 discard 命令，该命令会清空上面的 multistate 并把count设置为 0，然后修改 c->flags 去掉 REDIS_MULTI状态。

如果提交命令则键入EXEC命令，EXEC会把multistate的命令拿出来依次执行。等会我们结合watch一块来讲解EXEC。

##watch

来看 watch 命令，这个命令非常有用。我们假象一个这样的场景。如果没有 INCR 命令我们要自增加一个 key，我们会如何做?

        a = Redis.get(key)
        Redis.set(key, a+1)

看起来是个不错的方法，假设初值是 10,我们修改后应该为 11 的。如果在get、set之间另外一个client也执行了同样的操作也把 key 加 1。这样 key 本应该等于12,结果等于了 11。如何解决这种问题？

watch就是为此而生的。从watch开始到exec之间，一旦watch的key发生了变化，则提交失败，否则提交成功，从返回的结果里可以看出提交是否成功。代码如下

        >>> r = Redis.Redis("127.0.0.1", 6379, password="aliyundba") 
        >>> r.watch("a") 
        True
        >>> z = r.pipeline("a") 
        >>> z.set("a", 4) 
        <Redis.client.Pipeline object at 0xb7491d74> 
        >>> z.execute() 
        [True] 

    我们做依次中

        >>> r.watch("a") 
        True 
        >>> z = r.pipeline("a") 
        >>> z.set("a", 5) 
        <Redis.client.Pipeline object at 0xb74be8c4> 
        >>> z.execute() 
        Redis.exceptions.WatchError: Watched variable changed.

