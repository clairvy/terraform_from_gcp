default: run

GCLOUD_CMD =

run:
	env GCLOUD_CMD="$(GCLOUD_CMD)" ./a.pl
