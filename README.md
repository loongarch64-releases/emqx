# Emqx (LoongArch64 Build)

## 此 CI 构建使用的基础 Erlang 镜像没有 EMQX mnesia_hook 支持。EMQX 运行时使用`node.db_backend=mnesia` 配置，不支持 Cluster/rlog 模式。
