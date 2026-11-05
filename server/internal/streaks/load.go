package streaks

import (
	"context"

	"github.com/tahuffman1s/openword/server/internal/store"
)

// ForFriends loads the last Window days of 'learn' activity for userID and
// each of friendIDs in one query and computes the friend streak with each,
// as of today (the viewer's local calendar day).
func ForFriends(ctx context.Context, st store.Store, userID string, friendIDs []string, today string) (map[string]Friend, error) {
	out := make(map[string]Friend, len(friendIDs))
	if len(friendIDs) == 0 {
		return out, nil
	}
	ids := append([]string{userID}, friendIDs...)
	days, err := st.LearnDays(ctx, ids, AddDays(today, -Window))
	if err != nil {
		return nil, err
	}
	mine := days[userID]
	for _, fid := range friendIDs {
		out[fid] = Compute(mine, days[fid], today)
	}
	return out, nil
}
