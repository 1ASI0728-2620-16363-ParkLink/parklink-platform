# Redis scope

Redis is provisioned with AOF and an independent volume for future disposable discovery/conversation caching. It is not used by current application handlers and is not a reservation authority. Removing Redis must not change reservation correctness. Production Redis needs private networking, ACL credentials and TLS; do not expose the local unsecured instance.
