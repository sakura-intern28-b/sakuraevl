package handler

import (
	"database/sql"
	"net/http"
	"sakuravel/internal/model"
	"strings"
)

type postRecord struct {
	post   model.Post
	userID int64
}

type replyTarget struct {
	username    string
	displayName string
}

func sqlPlaceholders(n int) string {
	return strings.TrimRight(strings.Repeat("?,", n), ",")
}

func uniqueIDs(ids []int64) []int64 {
	seen := make(map[int64]struct{}, len(ids))
	result := make([]int64, 0, len(ids))
	for _, id := range ids {
		if _, ok := seen[id]; ok {
			continue
		}
		seen[id] = struct{}{}
		result = append(result, id)
	}
	return result
}

func int64Args(ids []int64) []any {
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	return args
}

// fetchPosts は複数投稿とその関連データをまとめて取得する。
// 一覧APIで投稿ごとにfetchPostを呼ばず、関連データを各種類1回ずつ取得する。
func (h *Handler) fetchPosts(r *http.Request, ids []int64, viewerID int64) ([]model.Post, error) {
	orderedIDs := uniqueIDs(ids)
	if len(orderedIDs) == 0 {
		return []model.Post{}, nil
	}

	records := make(map[int64]postRecord, len(orderedIDs))
	pending := orderedIDs
	for depth := 0; len(pending) > 0 && depth <= maxThreadDepth; depth++ {
		missing := make([]int64, 0, len(pending))
		for _, id := range pending {
			if _, ok := records[id]; !ok {
				missing = append(missing, id)
			}
		}
		if len(missing) == 0 {
			break
		}

		batch, err := h.fetchPostRecords(r, missing)
		if err != nil {
			return nil, err
		}
		for id, record := range batch {
			records[id] = record
		}

		next := make([]int64, 0)
		for _, id := range missing {
			record, ok := records[id]
			if !ok || !record.post.IsRepost || record.post.OriginalPostID == nil {
				continue
			}
			originalID := *record.post.OriginalPostID
			if originalID != id {
				if _, loaded := records[originalID]; !loaded {
					next = append(next, originalID)
				}
			}
		}
		pending = uniqueIDs(next)
	}

	for _, id := range orderedIDs {
		if _, ok := records[id]; !ok {
			return nil, sql.ErrNoRows
		}
	}

	allIDs := make([]int64, 0, len(records))
	userIDs := make([]int64, 0, len(records))
	for id, record := range records {
		allIDs = append(allIDs, id)
		userIDs = append(userIDs, record.userID)
	}
	allIDs = uniqueIDs(allIDs)
	userIDs = uniqueIDs(userIDs)

	users, err := h.fetchUsers(r, userIDs, viewerID)
	if err != nil {
		return nil, err
	}
	likesCounts, err := h.fetchPostCounts(r, "likes", allIDs)
	if err != nil {
		return nil, err
	}
	repostsCounts, err := h.fetchPostCounts(r, "reposts", allIDs)
	if err != nil {
		return nil, err
	}
	replyCounts, err := h.countRepliesBatch(r, allIDs)
	if err != nil {
		return nil, err
	}
	replyTargets, err := h.fetchReplyTargets(r, records)
	if err != nil {
		return nil, err
	}
	likedByMe, err := h.fetchViewerFlags(r, viewerID, "likes", allIDs)
	if err != nil {
		return nil, err
	}
	repostedByMe, err := h.fetchViewerFlags(r, viewerID, "reposts", allIDs)
	if err != nil {
		return nil, err
	}

	var build func(int64, map[int64]bool) (model.Post, bool)
	build = func(id int64, stack map[int64]bool) (model.Post, bool) {
		record, ok := records[id]
		if !ok {
			return model.Post{}, false
		}
		p := record.post
		p.Author = users[record.userID]
		p.LikesCount = likesCounts[p.ID]
		p.RepostsCount = repostsCounts[p.ID]
		p.RepliesCount = replyCounts[p.ID]
		p.LikedByMe = likedByMe[p.ID]
		p.RepostedByMe = repostedByMe[p.ID]

		if p.ParentPostID != nil {
			if target, ok := replyTargets[*p.ParentPostID]; ok {
				username := target.username
				displayName := target.displayName
				p.ReplyToUsername = &username
				p.ReplyToDisplayName = &displayName
			}
		}

		if p.IsRepost && p.OriginalPostID != nil && *p.OriginalPostID != p.ID {
			originalID := *p.OriginalPostID
			if !stack[originalID] {
				stack[originalID] = true
				original, ok := build(originalID, stack)
				delete(stack, originalID)
				if ok {
					p.OriginalPost = &original
				}
			}
		}
		return p, true
	}

	posts := make([]model.Post, 0, len(orderedIDs))
	for _, id := range orderedIDs {
		post, ok := build(id, map[int64]bool{id: true})
		if ok {
			posts = append(posts, post)
		}
	}
	return posts, nil
}

func (h *Handler) fetchPostRecords(r *http.Request, ids []int64) (map[int64]postRecord, error) {
	args := int64Args(ids)
	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT id, user_id, content, is_repost, original_post_id, parent_post_id, created_at
		FROM posts WHERE id IN (`+sqlPlaceholders(len(ids))+`)
	`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make(map[int64]postRecord, len(ids))
	for rows.Next() {
		var record postRecord
		if err := rows.Scan(
			&record.post.ID,
			&record.userID,
			&record.post.Content,
			&record.post.IsRepost,
			&record.post.OriginalPostID,
			&record.post.ParentPostID,
			&record.post.CreatedAt,
		); err != nil {
			return nil, err
		}
		result[record.post.ID] = record
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return result, nil
}

func (h *Handler) fetchUsers(r *http.Request, userIDs []int64, viewerID int64) (map[int64]model.User, error) {
	args := int64Args(userIDs)
	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT id, username, display_name, bio, created_at
		FROM users WHERE id IN (`+sqlPlaceholders(len(userIDs))+`)
	`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	users := make(map[int64]model.User, len(userIDs))
	for rows.Next() {
		var user model.User
		if err := rows.Scan(&user.ID, &user.Username, &user.DisplayName, &user.Bio, &user.CreatedAt); err != nil {
			return nil, err
		}
		user.AvatarColor = model.AvatarColor(user.ID)
		users[user.ID] = user
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	followers, err := h.fetchCounts(r, "SELECT followee_id, COUNT(*) FROM follows WHERE followee_id IN (", ") GROUP BY followee_id", userIDs)
	if err != nil {
		return nil, err
	}
	following, err := h.fetchCounts(r, "SELECT follower_id, COUNT(*) FROM follows WHERE follower_id IN (", ") GROUP BY follower_id", userIDs)
	if err != nil {
		return nil, err
	}
	postCounts, err := h.fetchCounts(r, "SELECT user_id, COUNT(*) FROM posts WHERE user_id IN (", ") GROUP BY user_id", userIDs)
	if err != nil {
		return nil, err
	}

	followedByMe := make(map[int64]bool)
	if viewerID > 0 {
		followArgs := append([]any{viewerID}, args...)
		followRows, err := h.DB.QueryContext(r.Context(),
			`SELECT followee_id FROM follows WHERE follower_id = ? AND followee_id IN (`+sqlPlaceholders(len(userIDs))+`)`,
			followArgs...,
		)
		if err != nil {
			return nil, err
		}
		for followRows.Next() {
			var followeeID int64
			if err := followRows.Scan(&followeeID); err != nil {
				followRows.Close()
				return nil, err
			}
			followedByMe[followeeID] = true
		}
		if err := followRows.Err(); err != nil {
			followRows.Close()
			return nil, err
		}
		followRows.Close()
	}

	for id, user := range users {
		user.FollowersCount = followers[id]
		user.FollowingCount = following[id]
		user.PostCount = postCounts[id]
		if viewerID > 0 && viewerID != id {
			user.FollowedByMe = followedByMe[id]
		}
		users[id] = user
	}
	return users, nil
}

func (h *Handler) fetchCounts(r *http.Request, prefix, suffix string, ids []int64) (map[int64]int, error) {
	args := int64Args(ids)
	rows, err := h.DB.QueryContext(r.Context(), prefix+sqlPlaceholders(len(ids))+suffix, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	counts := make(map[int64]int, len(ids))
	for rows.Next() {
		var id int64
		var count int
		if err := rows.Scan(&id, &count); err != nil {
			return nil, err
		}
		counts[id] = count
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return counts, nil
}

func (h *Handler) fetchPostCounts(r *http.Request, table string, ids []int64) (map[int64]int, error) {
	return h.fetchCounts(r,
		"SELECT post_id, COUNT(*) FROM "+table+" WHERE post_id IN (",
		") GROUP BY post_id",
		ids,
	)
}

func (h *Handler) fetchViewerFlags(r *http.Request, viewerID int64, table string, ids []int64) (map[int64]bool, error) {
	flags := make(map[int64]bool)
	if viewerID <= 0 || len(ids) == 0 {
		return flags, nil
	}
	args := append([]any{viewerID}, int64Args(ids)...)
	rows, err := h.DB.QueryContext(r.Context(),
		"SELECT post_id FROM "+table+" WHERE user_id = ? AND post_id IN ("+sqlPlaceholders(len(ids))+")",
		args...,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var postID int64
		if err := rows.Scan(&postID); err != nil {
			return nil, err
		}
		flags[postID] = true
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return flags, nil
}

func (h *Handler) fetchReplyTargets(r *http.Request, records map[int64]postRecord) (map[int64]replyTarget, error) {
	parentIDs := make([]int64, 0)
	for _, record := range records {
		if record.post.ParentPostID != nil {
			parentIDs = append(parentIDs, *record.post.ParentPostID)
		}
	}
	parentIDs = uniqueIDs(parentIDs)
	if len(parentIDs) == 0 {
		return map[int64]replyTarget{}, nil
	}

	rows, err := h.DB.QueryContext(r.Context(), `
		SELECT parent.id, u.username, u.display_name
		FROM posts parent JOIN users u ON u.id = parent.user_id
		WHERE parent.id IN (`+sqlPlaceholders(len(parentIDs))+`)
	`, int64Args(parentIDs)...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	targets := make(map[int64]replyTarget, len(parentIDs))
	for rows.Next() {
		var id int64
		var target replyTarget
		if err := rows.Scan(&id, &target.username, &target.displayName); err != nil {
			return nil, err
		}
		targets[id] = target
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return targets, nil
}

// countRepliesBatch は複数投稿の返信ツリーを深さごとにまとめて走査する。
func (h *Handler) countRepliesBatch(r *http.Request, postIDs []int64) (map[int64]int, error) {
	counts := make(map[int64]int, len(postIDs))
	type replyNode struct {
		id   int64
		root int64
	}
	frontier := make([]replyNode, 0, len(postIDs))
	visited := make(map[[2]int64]struct{})
	for _, id := range uniqueIDs(postIDs) {
		frontier = append(frontier, replyNode{id: id, root: id})
		visited[[2]int64{id, id}] = struct{}{}
	}

	for depth := 0; len(frontier) > 0 && depth < maxThreadDepth; depth++ {
		rootsByParent := make(map[int64]map[int64]struct{})
		parentIDs := make([]int64, 0, len(frontier))
		for _, node := range frontier {
			if _, ok := rootsByParent[node.id]; !ok {
				rootsByParent[node.id] = make(map[int64]struct{})
				parentIDs = append(parentIDs, node.id)
			}
			rootsByParent[node.id][node.root] = struct{}{}
		}

		rows, err := h.DB.QueryContext(r.Context(),
			`SELECT id, parent_post_id FROM posts WHERE parent_post_id IN (`+sqlPlaceholders(len(parentIDs))+`)`,
			int64Args(parentIDs)...,
		)
		if err != nil {
			return nil, err
		}
		next := make([]replyNode, 0)
		for rows.Next() {
			var childID, parentID int64
			if err := rows.Scan(&childID, &parentID); err != nil {
				rows.Close()
				return nil, err
			}
			for root := range rootsByParent[parentID] {
				key := [2]int64{root, childID}
				if _, alreadyVisited := visited[key]; alreadyVisited {
					continue
				}
				visited[key] = struct{}{}
				counts[root]++
				next = append(next, replyNode{id: childID, root: root})
			}
		}
		if err := rows.Err(); err != nil {
			rows.Close()
			return nil, err
		}
		rows.Close()
		frontier = next
	}
	return counts, nil
}
