# 翻译约定


## Redis 的各部分命令

* string 字符串
* hash 哈希表
* list 列表
* set 集合
* sorted set 有序集合
* pub/sub 发布/订阅
* transaction 事务
* scripting 脚本
* connection 连接
* server 服务器


## 相关术语

* replication 主从复制/复制
* master 主节点
* slave 附属节点
* event driven 事件驱动
* cluster 集群


## Redis 实现内部使用的一些数据结构

* sds（simple dynamic string） 动态字符串
* dict 字典
* hash 哈希表
* double-linked list 双链表
* skip list 跳跃表
* sentinel sentinel
* intset intset
* ziplist ziplist
* zipmap zipmap
