# 计数器

在日常的生活中，我们每天都和各式各样的计数器打交道。很大一类常见应用都可以归类为计数器，比如网页阅览量、帖子的回复数、邮件的未读计数等等，甚至是一些初看上去不那么像计数器的功能，比如自增 id 、收藏和投票，实际上都是计数器的一种。

在以下部分，文章会分别介绍简单计数器和唯一计数器。


## 简单计数器

就像名字所描述的一样，简单计数器主要用于计数逻辑非常简单直接的应用上，比如访问计数和网页阅览量统计，这类应用的最常见用法是，当某个给定时间发生的时候，对计数器加一。

简单计数器一般包含以下 API ：

``incr(counter, increment)`` 将给定增量增加到计数器上，并返回（增加操作执行之后）计数器的值。

``decr(counter, decrement)`` 将给定减量应用到计数器上，并返回（减法操作执行之后）计数器的值。

``get(counter)`` 返回计数器的当前值。

``reset(counter)`` 将计数器的值重置为 ``0`` 。

简单计数器可以用字符串和哈希两种方式实现，字符串的 API 相对简单一些：

    require 'redis'

    $redis = Redis.new

    def incr(counter, increment=1)
        return $redis.incrby(counter, increment)
    end

    def decr(counter, decrement=1)
        return $redis.decrby(counter, decrement)
    end

    def get(counter)
        value = $redis.get(counter)
        return value.to_i if value != nil
    end

    def reset(counter)
        value = $redis.set(counter, 0)
        return 0 if value == "OK"
    end

哈希实现将多个计数器放在同一个哈希上，因此需要一个额外的参数 ``hash`` 指定保存计数器的哈希：

    require 'redis'

    $redis = Redis.new

    def incr(hash, counter, increment=1)
        return $redis.hincrby(hash, counter, increment)
    end

    def decr(hash, counter, decrement=1)
        return $redis.hincrby(hash, counter, -decrement)
    end

    def get(hash, counter)
        value = $redis.hget(hash, counter)
        return value.to_i if value != nil
    end

    def reset(hash, counter)
        value = $redis.hset(hash, counter, 0)
        return 0
    end


## 实例：阅览量统计

以下是一个使用 [Sinatra 框架](http://www.sinatrarb.com/) 构建的网页阅览量统计的例子，每当有用户访问某本书的页面时，计数器就会给这本书的阅览量加上一：

    get '/book/:id' do
        pv = incr("page-view #{params[:id]}")
        # ...
    end

除此之外，我们还可以通过计数器来对访问次数进行限制。举个例子，以下代码就强制某个用户在一分钟里最多只能访问 30 次图书页面：

    get '/book/*' do
        key = '#{user_id} book-page-view'
        pv = incr(key)
        if pv == 1
            # 首次访问，设置过期时间
            $redis.expire(key, 60)
        elsif pv > 30
            # 访问次数过多
            error_message('visit too much time')
        else
            # ... 正常显示页面
        end
    end

这个访问限制器并不完美，因为它带有一个竞争条件：客户端可能会因为失败而忘记设置过期时间，从而导致每个用户只能访问图书页面 30 次，这真的会非常糟糕！ [INCR 命令的文档](http://redis.readthedocs.org/en/latest/string/incr.html) 详细地说明了如何构建一个正确的访问限制器。


## 实例：顺序自增标识符（sequential auto increment id）

在一些分布式数据库如 MongoDB 中，生成的键总是一个哈希值，比如 ``4da070180d03918e09fe7dad`` ，可以通过计数器生成一系列顺序自增标识符，来作为对用户友好的标识符。

顺序自增标识符的实现包装了计数器实现，它的完整定义如下：

    load 'string_simple_counter.rb'

    def generate_id(tag)
        return incr(tag)
    end

以下实例说明了如何生成一系列连续用户标识符：

    irb(main):001:0> load 'auto_id.rb'
    => true
    irb(main):002:0> generate_id('user')
    => 1
    irb(main):003:0> generate_id('user')
    => 2
    irb(main):004:0> generate_id('user')
    => 3


## 计数器的分类和实现

1) 数值计数器，可以按数值来增减的计数器。

可以使用字符串 ``INCR`` 、 ``DECR`` 和 ``INCRBY`` 等命令实现。

也可以使用哈希结构的 ``HSET`` ``HINCRBY`` 等命令实现。

2) 唯一计数器，针对每个对象，只计数一次。

可以使用集合的 ``SADD`` 、 ``SMEMBERS`` 等命令实现。


## 实例：唯一标识符（uid）

TODO


## 实例：喜欢/不喜欢

TODO
