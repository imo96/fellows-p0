"""myappdb.sqlite3 を作成する(Python 標準ライブラリのみ使用)。

使い方:  python create_db.py
同じフォルダの「テーブル定義書（myappdb）.sql」を実行して、myappdb.sqlite3 を作り直す。
既に myappdb.sqlite3 がある場合は、テーブルとデータが初期状態に戻る。
"""
import sqlite3
from pathlib import Path

here = Path(__file__).resolve().parent
sql_file = here / 'テーブル定義書（myappdb）.sql'
db_file = here / 'myappdb.sqlite3'

con = sqlite3.connect(db_file)
try:
    con.executescript(sql_file.read_text(encoding='utf-8'))
    con.commit()
    for t in ('商品', '注文', 'ユーザー情報', '廃番商品'):
        n = con.execute(f'SELECT COUNT(*) FROM "{t}"').fetchone()[0]
        print(f'{t}: {n} 件')
finally:
    con.close()
print(f'作成しました: {db_file}')
