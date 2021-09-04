# Adding your own config files

Contributing to this repository means helping out keeping all the config files up to date.
We're assuming that you do this because you use the Docker image `haugene/transmission-openvpn` and
you're lacking some configs or you want to update them because the provider has changed them.
All other uses of this repo is concidered "special interest" for now and will not be covered here.

Previously this was a bit more tricky because the configs lived in the main repo and you had to get your
configs into that repo to test them - and verify that they worked.
For those who are skilled at the command line and familiar with Docker you could of course build the image locally
but this project aims to make Docker accessible by those not too familiar with it as well so we wanted to make it simpler.

By separating the code itself and the configs you can actually run the official image and point it to your copy of the configs.
This way you can safely tinker along until it works and then submit a pull-request if you feel like helping out other users as well.


I'm assuming that you are able to run the image and follow the regular instructions and documentation for that.
This is steps you need to take in addition to that. So here we go.

This is the "add my own config" for dummies. Feel free to propose changes here to make it even simpler.

## Case 1: You have a config file (.ovpn) locally and you want to use it with the container

On the GitHub page for this config repository (assuming you're logged in):

1. Fork the repository (**wait until your fork is made**)
2. Click the "openvpn" folder of your fork

![Fork the repo](docs/images/fork_it.png)

Once you have your own copy of this repository you can start editing. You should have already navigated to the `openvpn` folder
and if you're adding a new provider or just doing your own "custom" provider this is where you start.

3. Click the "Add file" button and then "Create new file"

![Add file](docs/images/create_file.png)

4. Write a name for your config. It should be `<provider-name>/config.ovpn`. In this example our only goal is to run with
our own config so we write `provider/default.ovpn`. By calling the file `default.ovpn` we don't need to specify the name later.
For any provider the container will look for a file with that name if no else is given.

5. Paste the contents of your .ovpn file and press "Commit". You need to write a message describing your change.

![Commit it](docs/images/commit_it.png)

6. Now you can configure your container to use your version of the configs by setting the `GITHUB_CONFIG_SOURCE_REPO` environment variable. In my example that would be `GITHUB_CONFIG_SOURCE_REPO=example-user-one/vpn-configs-contrib`.

7. Since I called my provider just "provider" I would have to set `OPENVPN_PROVIDER=provider`

8. If I had called the config file something other than `default.ovpn` I would have to reference that with `OPENVPN_CONFIG=config-file-name`. Note that the config-file-name should be without `.ovpn` suffix.

Good luck!

**NB:** In this example I borrowed a config file from Torguard. They have their ca certificates inlined in the config.
Some providers have their certificates and keys as separate files and just reference them in the .ovpn file.
In these cases do step 3 again and add these files as well. Keep the file names like they are in your config bundle.

## Case 2: What do you want?

Is there another common use case you want a guide for? Open an issue or make it yourself and open a pull-request :)
