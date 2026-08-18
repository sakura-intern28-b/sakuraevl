CREATE INDEX idx_likes_post_created
    ON likes (post_id, created_at);

CREATE INDEX idx_likes_created_post
    ON likes (created_at, post_id);

CREATE INDEX idx_posts_parent_created_id
    ON posts (parent_post_id, created_at, id);
