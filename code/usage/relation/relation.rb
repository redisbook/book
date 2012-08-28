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


# 好友推荐

def recommend(my_id, target_id)
    return $redis.sdiff(following_key(target_id), following_key(my_id))
end


# 辅助函数

def following_key(id)
    return "#{id}::following"
end

def follower_key(id)
    return "#{id}::follower"
end
