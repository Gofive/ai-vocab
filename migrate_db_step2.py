#!/usr/bin/env python3
"""
数据库迁移脚本步骤2：删除 study_progress 表的 learned_count 字段
执行前会自动备份数据库
"""

import sqlite3
import shutil
from datetime import datetime
import os

DB_PATH = r'C:\Users\Administrator\Documents\vocab.db'
BACKUP_PATH = r'C:\Users\Administrator\Documents\vocab_backup_step2_{}.db'

def backup_database():
    """备份数据库"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = BACKUP_PATH.format(timestamp)
    shutil.copy2(DB_PATH, backup_file)
    print(f"✓ 数据库已备份到: {backup_file}")
    return backup_file

def check_table_structure(conn):
    """检查当前表结构"""
    cursor = conn.cursor()
    
    cursor.execute("PRAGMA table_info(study_progress)")
    columns = cursor.fetchall()
    
    print("→ 当前 study_progress 表结构:")
    for col in columns:
        print(f"  - {col[1]} ({col[2]})")
    
    has_learned_count = any(col[1] == 'learned_count' for col in columns)
    return has_learned_count

def migrate_table(conn):
    """迁移表结构：删除 learned_count 字段"""
    cursor = conn.cursor()
    
    # SQLite 不支持直接删除列，需要重建表
    print("→ 开始重建表...")
    
    # 1. 创建新表（不包含 learned_count）
    cursor.execute('''
        CREATE TABLE study_progress_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            dict_name TEXT UNIQUE NOT NULL,
            daily_words INTEGER DEFAULT 20,
            study_mode INTEGER DEFAULT 0,
            last_study_time TEXT,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    print("✓ 创建新表 study_progress_new")
    
    # 2. 复制数据（排除 learned_count）
    cursor.execute('''
        INSERT INTO study_progress_new 
        (id, dict_name, daily_words, study_mode, last_study_time, created_at)
        SELECT id, dict_name, daily_words, study_mode, last_study_time, created_at
        FROM study_progress
    ''')
    copied = cursor.rowcount
    print(f"✓ 复制了 {copied} 条记录")
    
    # 3. 删除旧表
    cursor.execute('DROP TABLE study_progress')
    print("✓ 删除旧表 study_progress")
    
    # 4. 重命名新表
    cursor.execute('ALTER TABLE study_progress_new RENAME TO study_progress')
    print("✓ 重命名新表为 study_progress")
    
    conn.commit()

def verify_migration(conn):
    """验证迁移结果"""
    cursor = conn.cursor()
    
    # 检查表结构
    cursor.execute("PRAGMA table_info(study_progress)")
    columns = cursor.fetchall()
    
    print("→ 新的 study_progress 表结构:")
    for col in columns:
        print(f"  - {col[1]} ({col[2]})")
    
    # 检查是否还有 learned_count 字段
    has_learned_count = any(col[1] == 'learned_count' for col in columns)
    if has_learned_count:
        print("✗ 错误：learned_count 字段仍然存在")
        return False
    
    print("✓ learned_count 字段已删除")
    
    # 检查数据完整性
    cursor.execute("SELECT COUNT(*) FROM study_progress")
    count = cursor.fetchone()[0]
    print(f"✓ study_progress 表中有 {count} 条记录")
    
    return True

def main():
    print("=" * 60)
    print("数据库迁移步骤2：删除 study_progress.learned_count 字段")
    print("=" * 60)
    print()
    
    # 检查数据库文件是否存在
    if not os.path.exists(DB_PATH):
        print(f"✗ 错误：数据库文件不存在: {DB_PATH}")
        return
    
    # 备份数据库
    print("步骤 1: 备份数据库")
    backup_file = backup_database()
    print()
    
    # 连接数据库
    print("步骤 2: 连接数据库")
    conn = sqlite3.connect(DB_PATH)
    print("✓ 已连接到数据库")
    print()
    
    try:
        # 检查表结构
        print("步骤 3: 检查当前表结构")
        has_learned_count = check_table_structure(conn)
        print()
        
        if not has_learned_count:
            print("✓ learned_count 字段不存在，无需迁移")
            print()
            return
        
        # 迁移表结构
        print("步骤 4: 迁移表结构")
        migrate_table(conn)
        print()
        
        # 验证迁移
        print("步骤 5: 验证迁移结果")
        if verify_migration(conn):
            print()
            print("=" * 60)
            print("✓ 迁移成功完成！")
            print("=" * 60)
            print()
            print(f"备份文件: {backup_file}")
            print("如果出现问题，可以使用备份文件恢复")
        else:
            print()
            print("=" * 60)
            print("✗ 迁移验证失败")
            print("=" * 60)
            print()
            print("请检查错误信息，必要时使用备份文件恢复")
    
    except Exception as e:
        print()
        print("=" * 60)
        print(f"✗ 迁移过程中出错: {e}")
        print("=" * 60)
        print()
        print(f"请使用备份文件恢复: {backup_file}")
        conn.rollback()
    
    finally:
        conn.close()
        print()
        print("数据库连接已关闭")

if __name__ == '__main__':
    main()
