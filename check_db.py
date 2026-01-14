import sqlite3

conn = sqlite3.connect(r'C:\Users\Administrator\Documents\vocab.db')
cursor = conn.cursor()

# 获取所有表
cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = cursor.fetchall()

print("=== 数据库表结构 ===\n")
for table in tables:
    table_name = table[0]
    print(f"表名: {table_name}")
    cursor.execute(f"SELECT sql FROM sqlite_master WHERE type='table' AND name='{table_name}'")
    schema = cursor.fetchone()[0]
    print(schema)
    print("\n" + "="*50 + "\n")

conn.close()
