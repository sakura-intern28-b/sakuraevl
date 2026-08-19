-- DBアプライアンスのデフォルト文字コードが utf8mb4 でないため、
-- 001_init.sql で CHARACTER SET を指定していなかった既存テーブルは
-- latin1 等で作成されてしまっている。日本語（display_name, bio, content 等）
-- を保存できるよう utf8mb4 に変換する。
ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE posts CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE sessions CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
