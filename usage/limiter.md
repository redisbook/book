# 限速器

TODO:

## 实例：阅览限速器

以下代码就强制某个用户在一分钟里最多只能访问 30 次图书页面：

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
