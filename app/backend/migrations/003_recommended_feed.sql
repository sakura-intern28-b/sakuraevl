CREATE TABLE IF NOT EXISTS recommended_posts (
    post_id         BIGINT    NOT NULL PRIMARY KEY,
    recent_likes    BIGINT    NOT NULL,
    post_created_at TIMESTAMP NOT NULL,
    refreshed_at    TIMESTAMP NOT NULL,
    INDEX idx_recommended_rank (recent_likes, post_created_at, post_id),
    CONSTRAINT fk_recommended_post
        FOREIGN KEY (post_id) REFERENCES posts (id) ON DELETE CASCADE
);

REPLACE INTO recommended_posts (post_id, recent_likes, post_created_at, refreshed_at)
SELECT p.id, COUNT(l.post_id), p.created_at, NOW()
FROM posts p
LEFT JOIN likes l
  ON l.post_id = p.id
 AND l.created_at > NOW() - INTERVAL 24 HOUR
WHERE p.parent_post_id IS NULL
GROUP BY p.id, p.created_at;

CREATE EVENT IF NOT EXISTS refresh_recommended_posts
ON SCHEDULE EVERY 1 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
DO
    REPLACE INTO recommended_posts (post_id, recent_likes, post_created_at, refreshed_at)
    SELECT p.id, COUNT(l.post_id), p.created_at, NOW()
    FROM posts p
    LEFT JOIN likes l
      ON l.post_id = p.id
     AND l.created_at > NOW() - INTERVAL 24 HOUR
    WHERE p.parent_post_id IS NULL
    GROUP BY p.id, p.created_at;
