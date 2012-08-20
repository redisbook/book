# 好友关系

好友关系是社交类网站最常见也是最重要的功能之一。

作为例子，以下是 twitter 网站上的好友关系截图，它显示了当前用户的关注数量、被关注数量，以及正在关注的用户：

![twitter好友关系实例图片](https://raw.github.com/redisbook/book/master/image/usage/twitter_relation.png)

文章接下来的部分会介绍如何实现这种的好友系统。


## API

一个基本的好友关系功能应该具有以下操作：

``follow(my_id, target_id)`` 关注给定用户。

``unfollow(my_id, target_id)`` 取消对给定用户的关注。

``following(my_id)`` 返回所有被我关注的人。

``count_following(my_id)`` 返回我关注的人数。

``follower(my_id)`` 返回所有关注我的人。

``count_follower(my_id)`` 返回关注我的人数。

另外还有两个谓词，用于检查两个用户之间的一对一关系：

``is_following?(my_id, target_id)`` 我是否正在关注给定用户？

``have_follower?(my_id, target_id)`` 给定用户是否正在关注我？


## 实现

好友关系可以通过对每个用户使用 ``following`` 和 ``follower`` 两个集合来构建： ``following`` 集合用于保存当前用户正在关注的人， ``follower`` 保存正在关注当前用户的人。

当一个用户对另一个用户进行 ``follow`` 动作的时候，程序将两个用户添加到彼此的集合中，而其他关系操作就通过对两个用户的集合进行处理来实现：

    require 'redis'

    $redis = Redis.new

    def follow(my_id, target_id)
        # 将目标添加到我的 following 集合里
        following_status = $redis.sadd(following_key(my_id), target_id)

        # 将我加到目标的 follower 集合里
        follower_status = $redis.sadd(follower_key(target_id), my_id)

        # 返回状态
        return following_status && follower_status
    end

    def unfollow(my_id, target_id)
        # 将目标从我的 following 集合中移除
        following_status = $redis.srem(following_key(my_id), target_id)

        # 将我从目标的 follower 集合中移除
        follower_status = $redis.srem(follower_key(target_id), my_id)

        # 返回状态
        return following_status && follower_status
    end


    # 关注

    def following(my_id)
        return $redis.smembers(following_key(my_id))
    end

    def count_following(my_id)
        return $redis.scard(following_key(my_id))
    end


    # 被关注

    def follower(my_id)
        return $redis.smembers(follower_key(my_id))
    end

    def count_follower(my_id)
        return $redis.scard(follower_key(my_id))
    end


    # 谓词

    def is_following?(my_id, target_id)
        return $redis.sismember(following_key(my_id), target_id)
    end

    def have_follower?(my_id, target_id)
        return is_following?(target_id, my_id)
    end


    # 辅助函数

    def following_key(id)
        return "#{id}::following"
    end

    def follower_key(id)
        return "#{id}::follower"
    end

测试：

    [huangz@mypad]$ irb
    irb(main):001:0> load 'relation.rb'
    => true
    irb(main):002:0> peter = 'user::10086'              # 用户 id
    => "user::10086"
    irb(main):003:0> jack = 'user::123123'
    => "user::123123"
    irb(main):004:0> follow(peter, jack)                # 关注和被关注
    => true
    irb(main):005:0> following(peter)
    => ["user::123123"]
    irb(main):006:0> follower(jack)
    => ["user::10086"]
    irb(main):007:0> is_following?(peter, jack)         # 谓词
    => true
    irb(main):008:0> have_follower?(jack, peter)
    => true
    irb(main):009:0> count_following(peter)             # 数量
    => 1
    irb(main):010:0> count_follower(jack)
    => 1


## 扩展：好友推荐

除了处理已有的好友关系外，关系系统通常还会为用户推荐一些他/她可能感兴趣的人。

举个例子，以下是 twitter 的好友推荐功能：

![twitter好友推荐示例图](https://raw.github.com/redisbook/book/master/image/usage/twitter_recommend.png)

使用 Redis 的集合操作，我们可以在好友关系实现的基础上，提供简单的好友推荐功能。

比如说，可以在用户 A 关注用户 B 之后，对用户 B 的 ``following`` 集合和用户 A 的 ``following`` 集合做一个差集操作，然后将结果推荐给用户 A ，鼓励他/她继续发现有趣的朋友。

以下是这一简单推荐系统的实现代码：

    def recommend(my_id, target_id)
        return $redis.sdiff(following_key(target_id), following_key(my_id))
    end

测试：

    irb(main):001:0> load 'relation.rb'
    => true
    irb(main):002:0> peter = 'user::10086'
    => "user::10086"
    irb(main):003:0> jack = 'user::123123'
    => "user::123123"
    irb(main):004:0> mary = 'user::12590'
    => "user::12590"
    irb(main):005:0> tom = 'user::228229'
    => "user::228229"
    irb(main):006:0> follow(peter, jack)
    => true
    irb(main):007:0> follow(peter, mary)
    => true
    irb(main):008:0> follow(tom, peter)
    => true
    irb(main):009:0> recommend(tom, peter)
    => ["user::123123", "user::12590"]      # 将 peter 正在关注的 jack 和 mary 推荐给 tom

更进一步的好友推荐功能可以通过对用户关系的集合进行数据挖掘来实现。
