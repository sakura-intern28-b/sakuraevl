REPLACE INTO recommended_posts (post_id, recent_likes, post_created_at, refreshed_at)
SELECT p.id, COALESCE(l.recent_likes, 0), p.created_at, NOW()
FROM posts p
LEFT JOIN (
    SELECT post_id, COUNT(*) AS recent_likes
    FROM likes
    WHERE created_at > NOW() - INTERVAL 24 HOUR
    GROUP BY post_id
) l ON l.post_id = p.id
WHERE p.parent_post_id IS NULL;

CREATE OR REPLACE EVENT refresh_recommended_posts
ON SCHEDULE EVERY 1 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
DO
    REPLACE INTO recommended_posts (post_id, recent_likes, post_created_at, refreshed_at)
    SELECT p.id, COALESCE(l.recent_likes, 0), p.created_at, NOW()
    FROM posts p
    LEFT JOIN (
        SELECT post_id, COUNT(*) AS recent_likes
        FROM likes
        WHERE created_at > NOW() - INTERVAL 24 HOUR
        GROUP BY post_id
    ) l ON l.post_id = p.id
    WHERE p.parent_post_id IS NULL;
