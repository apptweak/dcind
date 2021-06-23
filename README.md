# dcind (Docker-Compose-in-Docker)


### Versioning

This repository and corresponding images on Docker Hub follow the semantic versioning [rules](https://semver.org/). It is advised to not rely on the `latest` tag when using `apptweakci/dcind` image in your CI pipelines. Consider using a specific version, like `apptweakci/dcind`.

### Usage

Use this ```Dockerfile``` to build a base image for your integration tests in [Concourse CI](http://concourse.ci/). Alternatively, you can use a ready-to-use image from the Docker Hub: [apptweakci/dcind](https://hub.docker.com/r/apptweakci/dcind/). The image is Alpine based.

Here is an example of a Concourse [job](https://concourse-ci.org/jobs.html) that uses ```apptweakci/dcind``` image to run a bunch of containers in a task, and then runs the integration test suite. You can find a full version of this example in the [```example```](example) directory.

Note that `docker-lib.sh` has bash dependencies, so it is important to use `bash` in your task.

```yaml
  - name: integration
    plan:
      - aggregate:
        - get: code
          params: {depth: 1}
          passed: [unit-tests]
          trigger: true
        - get: docker-redis
          params: {save: true}
        - get: docker-busybox
          params: {save: true}
      - task: Run integration tests
        privileged: true
        config:
          platform: linux
          image_resource:
            type: registry-image
            source:
              repository: apptweakci/dcind
			  tag: latest
          inputs:
            - name: code
            - name: docker-redis
            - name: docker-busybox
          run:
            path: bash
            args:
              - -exc
              - |
                source /docker-lib.sh
                start_docker

                # Strictly speaking, preloading of Docker images is not required.
                # However, you might want to do this for a couple of reasons:
                # - If the image comes from a private repository, it is much easier to let Concourse pull it,
                #   and then pass it through to the task.
                # - When the image is passed to the task, Concourse can often get the image from its cache.
                load_images docker-redis docker-busybox
				wait

                # This is just to visually check in the log that images have been loaded successfully
                docker images

                # Run the container with tests and its dependencies.
                docker-compose --exit-code-from -f code/example/integration.yml run tests
				test_exit_code=$?

                # Cleanup.
                # Not sure if this is required.
                # It's quite possible that Concourse is smart enough to clean up the Docker mess itself.
                docker volume rm $(docker volume ls -q)

				exit "$test_exit_code"

```
