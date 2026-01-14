#!/usr/bin/env python3
"""
数据库迁移脚本：删除 word_progress 表
执行前会自动备份数据库
"""

import sqlite3
import shutil
from datetime import datetime
import os

DB_PATH = r'C:\Users\Administrator\Documents\vocab.db'
BACKUP_PATH = r'C:\Users\Administrator\Documents\vocab_backup_{}.db'

def backup_database():
    """备份数据库"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_file = BACKUP_PATH.format(timestamp)
    shutil.copy2(DB_PATH, backup_file)
    print(f"✓ 数据库已备份到: {backup_file}")
    return backup_file

def migrate_data(conn):
    """迁移 word_progress 表的数据到 user_study_progress"""
    cursor = conn.cursor()
    
    # 检查 word_progress 表是否存在
    cursor.execute("""
        SELECT name FROM sqlite_master 
        WHERE type='table' AND name='word_progress'
    """)
    
    if not cursor.fetchone():
        print("✓ word_progress 表不存在，无需迁移")
        return
    
    # 检查是否有数据需要迁移
    cursor.execute("SELECT COUNT(*) FROM word_progress")
    count = cursor.fetchone()[0]
    print(f"→ word_progress 表中有 {count} 条记录")
    
    if count > 0:
        # 迁移数据：将 is_learned=1 的记录迁移到 user_study_progress
        cursor.execute("""
            INSERT OR IGNORE INTO user_study_progress 
            (word_id, dict_name, state, last_modified)
            SELECT 
                word_id, 
                dict_name, 
                CASE WHEN is_learned = 1 THEN 1 ELSE 0 END as state,
                learn_time as last_modified
            FROM word_progress
        """)
        
        migrated = cursor.rowcount
        print(f"✓ 已迁移 {migrated} 条记录到 user_study_progress")
    
    conn.commit()

def drop_table(conn):
    """删除 word_progress 表"""
    cursor = conn.cursor()
    
    # 删除表
    cursor.execute("DROP TABLE IF EXISTS word_progress")
    print("✓ 已删除 word_progress 表")
    
    conn.commit()

def verify_migration(conn):
    """验证迁移结果"""
    cursor = conn.cursor()
    
    # 检查表是否已删除
    cursor.execute("""
        SELECT name FROM sqlite_master 
        WHERE type='table' AND name='word_progress'
    """)
    
    if cursor.fetchone():
        print("✗ 错误：word_progress 表仍然存在")
        return False
    
    # 检查 user_study_progress 表的数据
    cursor.execute("SELECT COUNT(*) FROM user_study_progress")
    count = cursor.fetchone()[0]
    print(f"✓ user_study_progress 表中有 {count} 条记录")
    
    return True

def main():
    print("=" * 60)
    print("数据库迁移：删除 word_progress 表")
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
        # 迁移数据
        print("步骤 3: 迁移数据")
        migrate_data(conn)
        print()
        
        # 删除表
        print("步骤 4: 删除 word_progress 表")
        drop_table(conn)
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
