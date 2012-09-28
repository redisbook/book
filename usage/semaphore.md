# 信号量

信号量用于限制同一资源可以被同时访问的数量。

它的基本操作有以下三个：

``init(name, size)`` 初始化信号量。

其中 ``name`` 参数为信号量的名字，而 ``size`` 则用于指定信号量的数量。

``acquire(name, timeout)`` 获取一个信号量。

如果获取成功，那么返回一个非空元素；如果获取失败，则返回一个 ``nil`` 。

其中 ``timeout`` 参数用于指定最长阻塞时间：如果调用 ``acquire`` 时没有信号量可用，那么就一直阻塞直到有信号量可用，或者 ``timeout`` 超时为止。默认 ``timeout`` 为 ``0`` ，也即是永远阻塞。

``release(name)`` 释放一个信号量。

客户端必须保证，只有获取了信号量的客户端能调用这个函数，否则会产生错误。


## 实现

信号量可以通过 Redis 的列表结构来实现：

当调用 ``init`` 函数初始化信号量时，我们将 ``size`` 数量的元素推入 key 为 ``name`` 的列表。

列表元素的内容不影响实现，只要不是 ``nil`` 就可以：这个实现将 ``size`` 个 ``name`` 字符串推入列表。如果担心字符串占用太多内存的话，也可以使用数字来代替，比如 ``1`` 。

    require "redis"

    $redis = Redis.new

    def init(name, size)
        item = [] << name
        all_item = item * size
        $redis.lpush(name, all_item)
    end

``acquire`` 函数可以使用 [BLPOP](http://redis.readthedocs.org/en/latest/list/blpop.html) 或者 [BRPOP](http://redis.readthedocs.org/en/latest/list/brpop.html) 实现。

通过这两个弹出命令的其中一个，函数对 key 为 ``name`` 的列表进行检查：如果列表不为空，表示有信号量可用；如果列表为空，那么说明暂时没有信号量可用。客户端阻塞直到 ``timeout`` 超时。

    def acquire(name, timeout=0)
         $redis.blpop(name, timeout)
    end

``release`` 函数将一个元素推入 key 为 ``name`` 的列表，从而释放一个信号量。

注意这个实现并没有对客户端进行任何检查，也即是，函数只管推入元素，不管这个客户端是否真的获取过信号量。这也是前面列出 API 时，要求调用者必须自己进行检查的原因。

    def release(name)
        $redis.lpush(name, name)
    end


## 参考资料

[维基百科 Semaphore 词条](http://en.wikipedia.org/wiki/Semaphore_\(programming\))
