package db

import "testing"

func TestMigrationsLoadInOrder(t *testing.T) {
	vs, err := MigrationVersions()
	if err != nil {
		t.Fatal(err)
	}
	if len(vs) == 0 {
		t.Fatal("no migrations embedded")
	}
	for i := 1; i < len(vs); i++ {
		if vs[i] <= vs[i-1] {
			t.Fatalf("migrations not strictly increasing: %v", vs)
		}
	}
}
