default: run

GCLOUD_CMD =

run:
	env GCLOUD_CMD="$(GCLOUD_CMD)" ./terraform_from_gcp.pl

clean:
	$(RM) $(RMF) *~ .*~ **/*~ **/.*~
