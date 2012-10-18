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

现在，要查看某个图书页面的点击量，调用 ``get("page-view #{id}")`` 就可以了。


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


## 唯一计数器

和简单计数器不同，唯一计数器对每个记录实体只计数一次。

比如说，在 [StackOverflow](http://stackoverflow.com/) 网站上，用户可以对问题和答案进行提升和下沉投票，而且每个用户只能投票一次：

![投票示例](https://raw.github.com/redisbook/book/bb003b6a7ec203fed21e64c392997fdbc440ad11/image/usage/vote.png)

这种投票系统就是唯一计数器的一个例子。

以下是唯一计数器的基本 API ：

``add(counter, obj)`` 将对象加入到计数器中，如果对象已经存在，返回 ``false`` ；添加成功返回 ``true`` 。

``remove(counter, obj)`` 从计数器中移除对象 ``obj`` ，如果 ``obj`` 并不是计数器的对象，那么返回 ``false`` ；移除成功返回 ``true`` 。

``is_member?(counter, obj)`` 检查 ``obj`` 是否已经存在于计数器。

``members(counter)`` 返回计数器包括的所有成员对象。

``count(counter)`` 返回计数器所有成员对象的数量。

唯一计数器的 API 和简单计数器的 API 有些不同，而且唯一计数器的底层是使用 Redis 的集合来实现的，它的完整定义如下：

    require 'redis'

    $redis = Redis.new

    def add(counter, member)
        return $redis.sadd(counter, member)
    end

    def remove(counter, member)
        return $redis.srem(counter, member)
    end

    def is_member?(counter ,member)
        return $redis.sismember(counter, member)
    end

    def members(counter)
        return $redis.members(counter)
    end

    def count(counter)
        return $redis.scard(counter)
    end


## 实例：提升/下沉投票

有了详细的 API 和实现之后，现在完成一个完整的提升/下沉投票实现了（有些网站也将这个功能称为有用/没用，或者喜欢/不喜欢）。

对于每个问题，我们使用两个唯一计数器，分别计算提升和下沉投票，并且在每次投票前检查唯一计数器，确保不会出现重复投票。

以下是投票系统的详细实现：

    load 'unique_counter.rb'

    def vote_up(question_id, user_id)
        if voted?(question_id, user_id)
            raise "alread voted"
        end
        return add("question-vote-up #{question_id}", user_id)
    end

    def vote_down(question_id, user_id)
        if voted?(question_id, user_id)
            raise "alread voted"
        end
        return add("question-vote-down #{question_id}", user_id)
    end

    def voted?(question_id, user_id)
        return (is_member?("question-vote-up #{question_id}", user_id) or \
                is_member?("question-vote-down #{question_id}", user_id))
    end

    def count_vote_up(question_id)
        return count("question-vote-up #{question_id}")
    end

    def count_vote_down(question_id)
        return count("question-vote-down #{question_id}")
    end

测试：

    irb(main):001:0> load 'vote_question.rb'
    => true
    irb(main):002:0> vote_up(10086, 123)        # 投票
    => true
    irb(main):003:0> vote_up(10086, 456)
    => true
    irb(main):004:0> vote_down(10086, 789)
    => true
    irb(main):005:0> count_vote_up(10086)       # 计数
    => 2
    irb(main):006:0> count_vote_down(10086)
    => 1
    irb(main):007:0> vote_up(10086, 123)        # 不能重复投票
    RuntimeError: alread voted
        from vote_question.rb:5:in `vote_up'
        from (irb):7
        from /usr/bin/irb:12:in `<main>'
