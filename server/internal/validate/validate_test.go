package validate

import "testing"

func TestUsername(t *testing.T) {
	good := map[string]string{"Alice": "alice", " bob_1 ": "bob_1", "abc": "abc"}
	for in, want := range good {
		got, err := Username(in)
		if err != nil || got != want {
			t.Errorf("Username(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	for _, bad := range []string{"", "ab", "has space", "ünïcode", "toolongtoolongtoolongtoolong", "dash-ed"} {
		if _, err := Username(bad); err == nil {
			t.Errorf("Username(%q) should fail", bad)
		}
	}
}

func TestPassword(t *testing.T) {
	if err := Password("short"); err == nil {
		t.Error("short password accepted")
	}
	if err := Password("longenough"); err != nil {
		t.Error(err)
	}
	if err := Password("ünïcödé1"); err != nil { // 8 runes
		t.Error(err)
	}
}

func TestEmail(t *testing.T) {
	got, err := Email(" Bob@Example.COM ")
	if err != nil || got != "bob@example.com" {
		t.Errorf("got %q, %v", got, err)
	}
	for _, bad := range []string{"", "nope", "a@", "Bob <bob@example.com>", "@x.com"} {
		if _, err := Email(bad); err == nil {
			t.Errorf("Email(%q) should fail", bad)
		}
	}
}

func TestDay(t *testing.T) {
	if err := Day("2026-02-28"); err != nil {
		t.Error(err)
	}
	for _, bad := range []string{"2026-2-8", "2026-13-01", "2026-02-30", "26-02-08", "2026/02/08"} {
		if err := Day(bad); err == nil {
			t.Errorf("Day(%q) should fail", bad)
		}
	}
}

func TestReminderTimeAndZone(t *testing.T) {
	for _, ok := range []string{"00:00", "07:30", "23:59"} {
		if err := ReminderTime(ok); err != nil {
			t.Error(ok, err)
		}
	}
	for _, bad := range []string{"24:00", "7:30", "07:60", "0730", ""} {
		if err := ReminderTime(bad); err == nil {
			t.Errorf("ReminderTime(%q) should fail", bad)
		}
	}
	if err := TimeZone("Europe/London"); err != nil {
		t.Error(err)
	}
	for _, bad := range []string{"", "Local", "Mars/Olympus"} {
		if err := TimeZone(bad); err == nil {
			t.Errorf("TimeZone(%q) should fail", bad)
		}
	}
}

func TestKindsAndDays(t *testing.T) {
	if err := ActivityKind("learn"); err != nil {
		t.Error(err)
	}
	if err := ActivityKind("sleep"); err == nil {
		t.Error("bad kind accepted")
	}
	if err := AchievementKind("badge"); err != nil {
		t.Error(err)
	}
	if err := AchievementKind("trophy"); err == nil {
		t.Error("bad kind accepted")
	}
	if err := ReminderDays(127); err != nil {
		t.Error(err)
	}
	if err := ReminderDays(128); err == nil {
		t.Error("128 accepted")
	}
	if _, err := DisplayName("   "); err == nil {
		t.Error("blank display name accepted")
	}
	if _, err := Bio(string(make([]rune, 161))); err == nil {
		t.Error("long bio accepted")
	}
}
