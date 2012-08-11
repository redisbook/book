# 缓存

缓存是 Redis 最常见的用法之一，常用的键-值缓存可以用字符串或者哈希来实现。


## API

一个最基本的缓存系统应该有以下两个基本操作：

``set(key, value, timeout=nil)``

设置缓存 ``key`` 的值为 ``value`` 。参数 ``timeout`` 是可选的，它决定缓存的生存时间，以秒为单位。

``get(key)``

获取缓存 ``key`` 的值。

一些更复杂的缓存系统可能会有 ``get_multi_key`` 、 ``set_if_not_exists`` 、 ``delete`` 或者 ``set_timeout`` 和 ``get_timeout`` 等操作。

以下两个小节分别介绍字符串缓存和哈希缓存的实现。


## 字符串缓存

字符串的实现非常简单和直观，只需将相应的 Redis 命令，比如 [SET](http://redis.readthedocs.org/en/latest/string/set.html) 、 [SETEX](http://redis.readthedocs.org/en/latest/string/setex.html) 和 [GET](http://redis.readthedocs.org/en/latest/string/get.html) 分别用函数包裹起来就可以了：

    require 'redis'

    $redis = Redis.new

    def set(key, value, timeout=nil)
        if timeout == nil 
            return $redis.set(key, value)
        else
            return $redis.setex(key, timeout, value)
        end 
    end

    def get(key)
        return $redis.get(key)
    end

测试：

    irb(main):001:0> load 'string_cache.rb'
    => true
    irb(main):002:0> set('key', 'value')
    => "OK"
    irb(main):003:0> get('key')
    => "value"
    irb(main):004:0> $redis.ttl('key')          # 没有给定 timeout, 所以没有设置 ttl
    => -1
    irb(main):005:0> set('another-key', 'another-value', 10086)
    => "OK"
    irb(main):006:0> get('another-key')
    => "another-value"
    irb(main):007:0> $redis.ttl('another-key')  # 给定了 timeout 参数
    => 10074


## 哈希缓存

哈希缓存将多个缓存保存到同一个哈希中，使用者需要指定哈希的名字，这可以通过全局变量或者添加多一个参数来完成。

除此之外，因为 Redis 并不提供为哈希中的单个 ``key`` 设置过期时间的功能，所以在这个实现中，我们去掉 ``set`` 操作设置过期时间的功能，而单独使用一个 ``expire`` 操作来设置哈希的过期时间。

修改之后的 API 如下：

``set(hash_name, key, value)``

``get(hash_name, key)``

``expire(hash_name, timeout)``

实现的定义如下：

    require 'redis'

    $redis = Redis.new

    def set(hash_name, key, value)
        return $redis.hset(hash_name, key, value)
    end

    def get(hash_name, key)
        return $redis.hget(hash_name, key)
    end

    def expire(hash_name, timeout)
        return $redis.expire(hash_name, timeout)
    end

测试：

    irb(main):001:0> load 'hash_cache.rb'
    => true
    irb(main):002:0> set('greeting', 'morning', 'good morning!')
    => true
    irb(main):003:0> get('greeting', 'morning')
    => "good morning!"
    irb(main):004:0> set('greeting', 'night', 'good night!')
    => true
    irb(main):005:0> get('greeting', 'night')
    => "good night!"
    irb(main):006:0> $redis.hgetall('greeting')
    => {"morning"=>"good morning!", "night"=>"good night!"}
    irb(main):007:0> $redis.ttl('greeting')
    => -1
    irb(main):008:0> expire('greeting', 10086)
    => true
    irb(main):009:0> $redis.ttl('greeting')
    => 10085


## 两种缓存方式之间的功能对比

字符串缓存为每个缓存设置一个单独的 ``key`` ，因此每个字符串缓存可以单独控制自己的过期时间。哈希缓存将多个缓存保存到同一个哈希 ``key`` 中，因此整个哈希共享同一个过期时间。

一般来说，对于单个缓存操作来说，字符串缓存更灵活，但是在一些情况下，哈希缓存提供的对多个缓存的操作也非常有用。

举个例子，你可以将多个 Redis 相关的文章缓存到 ``Redis`` 哈希下，如果你对多个 Redis 文章进行了批量修改，之后只要删掉 ``Redis`` 哈希，就可以激活缓存的更新：

    set('Redis', 'Redis 源码分析(1)', '...')
    set('Redis', 'Redis 源码分析(2)', '...')
    set('Redis', 'Redis 源码分析(3)', '...')

    # 对多个 Redis 文章进行批量修改

    $redis.del('Redis')

    # 之后所有 Redis 文章的缓存都要重新设置

另一方面，使用字符串缓存来做同样的事情却复杂得多：

    # 需要保证每个字符串 key 都使用同样的前缀

    set('Redis 源码分析(1)', '...')
    set('Redis 源码分析(2)', '...')
    set('Redis 源码分析(3)', '...')

    # 对多个 Redis 文章进行批量修改

    # 遍历并删除所有相关文章的缓存
    $redis.keys('Redis *').each do |key|    
        $redis.del(key)
    end

    # 之后所有 Redis 文章的缓存都要重新设置

从以上的代码也可以看出对多个字符串缓存进行操作的限制：如果某篇 Redis 文章不是以 'Redis ' 开头的话，那么它就不会出现在 [KEYS 命令](http://redis.readthedocs.org/en/latest/key/keys.html) 的输出结果中。

另一个关于字符串缓存和哈希缓存的重要区别是，使用哈希缓存更节省内存，Redis 的官方网站介绍了如何使用哈希结构来代替字符串结构，从而节省大量内存的例子： [memory-optimization topic](http://redis.io/topics/memory-optimization) 。
