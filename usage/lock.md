# 锁

当多个请求争抢同一资源的情况出现时，就需要使用锁来进行访问控制。

Redis 并没有直接提供锁操作原语，但是我们可以通过现有的命令来实现锁。

编写锁的实现必须非常小心，因为一个不起眼的缺陷就可能导致[竞争条件](http://en.wikipedia.org/wiki/Race_condition)发生，作为例子，稍后我们就会看到一些不正确的、或是带有竞争条件的锁实现。

除此之外，锁还需要一些强制机制，比如超时限制，以避免发生[死锁](http://en.wikipedia.org/wiki/Deadlock)。


## API

最简单的锁只有两个操作，一个是请求锁，另一个是释放锁，这两个操作的 API 如下：

    acquire(key, timeout, uid)

    release(key, uid)

``key`` 是锁的名称，一个安全的锁要确保在每个时间点上，只能有一个客户端持有名称为 ``key`` 的锁。

``timeout`` 决定了加锁的最长时间，当一个客户端持有锁超过 ``timeout`` 秒之后，这个锁就会自动释放。

在一些实现中， ``timeout`` 并不是必须的，客户端可以持有锁任意长的时间。
为了防止客户端在持有锁之后失败，从而导致死锁，这个实现强制客户端必须指定一个最长加锁时间。

另外要说明的是，虽然锁可以自动被释放，但客户端有时候也会需要手动释放锁。
举个例子，一个客户端可能申请了 10 秒钟的加锁时间，但是只用了 5 秒钟就完成了工作，那么它就可以调用 ``release`` 手动释放锁，把剩下的 5 秒加锁时间节约下来给下一个加锁客户端。这就是将 ``release`` 操作包含在 API 中的原因。

``uid`` 由客户端给出，在执行 ``release`` 时需要比对给定的 ``uid`` 是否就是加锁客户端的 ``uid`` ，从而实现身份验证，确保只有持有锁的客户端可以释放锁。


## 实现

初看上去， ``acquire`` 操作似乎可以用 [SETEX](http://redis.readthedocs.org/en/latest/string/setex.html) 命令实现，调用 ``acquire(key, timeout, uid)`` 等同于执行：

    SETEX name timeout uid

这种实现的问题是， ``SETEX`` 命令会直接覆盖已有的值，因此多个客户端的加锁请求会互相覆盖，所以这个实现是不安全的。

另一种可能的办法是，组合使用 [SETNX](http://redis.readthedocs.org/en/latest/string/setnx.html) 命令和 [EXPIRE](http://redis.readthedocs.org/en/latest/key/expire.html) 命令，其中 ``SETNX`` 命令用于加锁，它的返回值决定了客户端是否成功获取锁，如果锁获取成功，就用 ``EXPIRE`` 命令给锁加上超时时间：

    if SETNX key uid == "OK"
        EXPIRE key timeout
    end

不幸的是，这种实现也不安全：因为在 ``SETNX`` 执行之后、 ``EXPIRE`` 命令执行之前的这段时间内，客户端可能会失败，造成 ``EXPIRE`` 命令没办法执行，从而形成死锁。

解决问题的关键是，让 ``acquire`` （当然还有 ``release`` ）成为一个[原子操作](http://en.wikipedia.org/wiki/Atomic_operation)，可以用事务或脚本两种方法来实现这一点，以下两个小节分别讲解这两种实现方式。


## 事务实现

这个实现通过使用事务和 [WATCH](http://redis.readthedocs.org/en/latest/transaction/watch.html) 命令来保证 ``acquire`` 和 ``release`` 的原子性。

``acquire`` 操作定义如下：

    # coding: utf-8

    require "redis"

    $redis = Redis.new

    def acquire(key, timeout, uid)

        $redis.watch(key)

        # 已经被其他客户端加锁？
        if $redis.exists(key)
            $redis.unwatch
            return false
        end

        # 尝试加锁
        result = $redis.multi do |t|
            t.setex(key, timeout, uid)
        end

        # 加锁成功？
        return result != nil

    end

函数首先使用 ``WATCH`` 命令监视 ``key`` ，然后查看这个 ``key`` 是否已经有值，也即是，这个锁是否已经被其他客户端加锁。

如果 ``key`` 没有值的话，它就执行一个事务，事务里使用 ``SETEX`` 命令设置锁的 ``uid`` 和最长加锁时间 ``timeout`` 。

``WATCH`` 命令的效果保证，如果在 ``WATCH`` 执行之后、事务执行之前，有其他别的客户端修改了 ``key`` 的话，那么这个客户端的事务执行就会失败。

Ruby 客户端通过返回 ``nil`` 来表示事务失败，因此函数的最后通过验证事务结果是否不为 ``nil`` ，来判断加锁是否成功。

``release`` 函数的定义和 ``acquire`` 函数类似，也同样使用了事务和 ``WATCH`` 命令来保证原子性，并且它在解锁之前，会先验证 ``key`` 的值（也即是 ``uid`` ），确保只有持有锁的客户端可以释放锁：

    def release(key, uid)

        $redis.watch(key)

        # 锁不存在或已经释放？
        if $redis.exists(key) == false
            $redis.unwatch
            return true
        end

        # 比对 uid ，如果匹配就删除 key
        if uid == $redis.get(key)
            result = $redis.multi do |t|
                t.del(key)
            end
            # 删除成功？
            return result != nil
        else
            return false
        end

    end

测试：

    irb(main):001:0> load 'lock_transaction_implement.rb'
    => true
    irb(main):002:0> acquire('lock', 10086, 'moto')
    => true
    irb(main):003:0> acquire('lock', 123, 'nokia')      # 加锁失败
    => false
    irb(main):004:0> release('lock', 'nokia')           # 释放锁失败， uid 不匹配
    => false
    irb(main):005:0> release('lock', 'moto')
    => true


## 脚本实现

在 2.6 或以上版本的 Redis 中，更好的实现锁的办法是使用 Lua 脚本：Redis 确保 [EVAL](http://redis.readthedocs.org/en/latest/script/eval.html) 命令执行的脚本总是原子性的，因此我们可以直接在 Lua 脚本里执行加锁和释放锁的操作，而不必担心任何竞争条件，只要考虑脚本程序的正确性就可以了。

以下是这一实现的完整源码：

    # coding: utf-8

    require "redis"

    $redis = Redis.new

    def acquire(key, timeout, uid)

        script = "
            if redis.call('exists', KEYS[1]) == 0 then
                return redis.call('setex', KEYS[1], ARGV[1], ARGV[2])
            end
        "

        return "OK" == $redis.eval(script, :keys => [key], :argv => [timeout, uid])

    end

    def release(key, uid)
        
        script = "
            if redis.call('get', KEYS[1]) == ARGV[1] then
                return redis.call('del', KEYS[1])
            end
        "

        return 1 == $redis.eval(script, :keys => [key], :argv => [uid])

    end   

注意这里 ``Redis.eval`` 方法的 API 和 Redis ``EVAL`` 命令稍有不同， ``EVAL`` 命令要求给出 ``keys`` 参数的个数，而 ``Redis.eval`` 方法会在执行时，通过计算 ``keys`` 数组的长度，自动将这个参数加上，因此不必显式地指定 ``keys`` 参数的个数。

测试：

    irb(main):001:0> load 'lock_scripting_implement.rb'
    => true
    irb(main):002:0> acquire('lock', 10086, 'moto')
    => true
    irb(main):003:0> acquire('lock', 123, 'nokia')
    => false
    irb(main):004:0> release('lock', 'nokia')
    => false
    irb(main):005:0> release('lock', 'moto')
    => true


## 两种实现的对比

事务实现的好处是，它可以用在 2.2 或以上版本的 Redis 里，缺点是事务和 ``WATCH`` 的处理非常复杂，容易出错。

脚本实现只能运行在 Redis 2.6 或以上的版本，但脚本实现相比事务实现要简单得多。

目前两种实现都可以在最新的 Redis 2.6 和 Redis 3.0 上使用，但根据 [Redis 官网上的介绍](http://redis.io/topics/transactions)，未来可能会去掉事务功能，只保留脚本。

因此，如果没有其他别的原因，请优先使用脚本实现。


## 参考资料

[维基百科 Lock(computer science) 词条](http://en.wikipedia.org/wiki/Lock_\(computer_science\))
