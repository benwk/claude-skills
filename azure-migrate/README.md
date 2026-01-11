# Azure Migration Tools

通用的Azure资源迁移工具，支持PostgreSQL数据库和Storage Account的跨订阅、跨区域迁移。

## 工具列表

1. **migrate_postgresql.sh** - PostgreSQL数据库迁移工具
2. **migrate_storage.sh** - Azure Storage Account迁移工具

## 安装

```bash
# 将脚本移动到可执行路径
sudo cp migrate_postgresql.sh /usr/local/bin/
sudo cp migrate_storage.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/migrate_postgresql.sh
sudo chmod +x /usr/local/bin/migrate_storage.sh
```

## PostgreSQL迁移工具

### 功能
- 自动从Key Vault获取密码
- 支持多数据库批量迁移
- 使用pg_dump/pg_restore进行完整备份和恢复
- 内置数据验证功能
- 支持仅验证模式

### 使用方法

1. 创建源环境配置文件 `source_db.json`:
```json
{
  "subscription": "00000000-0000-0000-0000-000000000001",
  "host": "psql-mycompany-prod.postgres.database.azure.com",
  "username": "psqladmin",
  "keyvault": "kv-mycompany-prod",
  "databases": ["app_production", "analytics", "users"]
}
```

2. 创建目标环境配置文件 `target_db.json`:
```json
{
  "subscription": "00000000-0000-0000-0000-000000000002",
  "host": "psql-mycompany-staging.postgres.database.azure.com",
  "username": "psqladmin",
  "keyvault": "kv-mycompany-staging",
  "databases": ["app_production", "analytics", "users"]
}
```

**示例文件**: 参考 `examples/source_db.json.example` 和 `examples/target_db.json.example`

3. 执行迁移:
```bash
# 完整迁移（备份 + 恢复 + 验证）
migrate_postgresql.sh source_db.json target_db.json

# 仅验证数据
migrate_postgresql.sh source_db.json target_db.json --verify-only

# 使用已有备份
migrate_postgresql.sh source_db.json target_db.json --skip-backup --backup-dir /tmp/existing_backup
```

### 命令选项

- `--verify-only` - 仅验证数据，不执行迁移
- `--skip-backup` - 跳过备份步骤（使用已有备份）
- `--backup-dir DIR` - 指定备份目录
- `--help` - 显示帮助信息

## Storage Account迁移工具

### 功能
- 使用SAS token进行安全传输
- 支持多容器批量迁移
- 通过本地临时存储进行三步迁移（源→本地→目标）
- 自动创建目标容器
- 内置文件数量验证

### 使用方法

1. 创建源存储配置文件 `source_storage.json`:
```json
{
  "subscription": "00000000-0000-0000-0000-000000000001",
  "account_name": "stmycompanyprod",
  "resource_group": "rg-mycompany-prod",
  "containers": ["uploads", "static", "backups"]
}
```

2. 创建目标存储配置文件 `target_storage.json`:
```json
{
  "subscription": "00000000-0000-0000-0000-000000000002",
  "account_name": "stmycompanystaging",
  "resource_group": "rg-mycompany-staging",
  "containers": ["uploads", "static", "backups"]
}
```

**示例文件**: 参考 `examples/source_storage.json.example` 和 `examples/target_storage.json.example`

3. 执行迁移:
```bash
# 完整迁移（下载 + 上传 + 验证）
migrate_storage.sh source_storage.json target_storage.json

# 仅验证数据
migrate_storage.sh source_storage.json target_storage.json --verify-only

# 跳过下载（使用已下载的本地文件）
migrate_storage.sh source_storage.json target_storage.json --skip-download --temp-dir /tmp/existing_files
```

### 命令选项

- `--verify-only` - 仅验证文件数量，不执行迁移
- `--skip-download` - 跳过下载步骤（使用已有本地文件）
- `--temp-dir DIR` - 指定临时目录
- `--help` - 显示帮助信息

## 验证

两个工具都包含内置验证功能：

- **PostgreSQL**: 使用 `COUNT(*)` 准确统计所有表的行数并对比
- **Storage Account**: 统计blob数量并对比

验证报告会在迁移完成后自动生成。

## 示例工作流

### 完整环境迁移

```bash
# 1. 迁移数据库
migrate_postgresql.sh source_db.json target_db.json

# 2. 迁移存储
migrate_storage.sh source_storage.json target_storage.json

# 3. 最终验证
migrate_postgresql.sh source_db.json target_db.json --verify-only
migrate_storage.sh source_storage.json target_storage.json --verify-only
```

### 灾难恢复测试

```bash
# 1. 仅备份生产数据
migrate_postgresql.sh production_db.json - --backup-dir /backup/daily_$(date +%Y%m%d)

# 2. 验证备份完整性
migrate_postgresql.sh production_db.json dr_db.json --verify-only
```

## 依赖项

- Azure CLI (az)
- PostgreSQL client tools (psql, pg_dump, pg_restore)
- azcopy
- jq

## 安全注意事项

1. 配置文件不包含密码，密码从Key Vault自动获取
2. SAS token有4小时过期时间
3. 临时文件在迁移完成后自动清理
4. 建议在非生产时间执行大规模迁移

## 故障排除

### PostgreSQL连接失败
- 检查防火墙规则
- 确认Key Vault访问权限
- 验证订阅ID是否正确

### Storage传输失败
- 检查azcopy日志：`~/.azcopy/*.log`
- 确认网络连接稳定
- 验证SAS token未过期

## 许可证

内部工具，仅供项目使用。
