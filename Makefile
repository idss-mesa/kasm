platform = linux/amd64
repo = harbor.cyverse.org/vice/mesa-kasm
tag = latest
context = latest
repotag = $(repo):$(tag)

build:
	docker buildx build --rm --platform "$(platform)" -t "$(repotag)" --load "$(context)/"

push:
	docker push "$(repotag)"

run:
	docker run --rm --shm-size=512m -p 6901:6901 -e IPLANT_USER=$$USER "$(repotag)"

rmi:
	docker rmi "$(repotag)"
