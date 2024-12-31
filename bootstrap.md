# Bootstrap.sh Tool Guide

The `bootstrap.sh` script provides a streamlined interface for managing Vagrant environments with various commands. It also enables interactive configuration during the first setup, allowing decisions to be recorded and reused for subsequent operations.

## Usage
Run the script with the appropriate argument to perform specific actions on your Vagrant environment.

- **Interactive Setup:**
  During the initial setup, the script may prompt you with questions to configure the environment. For example:
  ```
  Do you want to make a jenkins on k8s in Vagrant Master / Slave? (M/S)
  ```
  Your choice will be recorded and automatically applied for future reloads or provisions.

### Commands

- **Initialize or Reload Environment**
  ```bash
  bash bootstrap.sh
  ```
  - **From scratch:** Executes `vagrant up` to initialize the Vagrant environment.
  - **Otherwise:** Executes `vagrant reload` to reload the existing environment based on previous decisions.

- **Halt Environment**
  ```bash
  bash bootstrap.sh halt
  ```
  - Halts the Vagrant environment.
  - Equivalent to:
    ```bash
    vagrant halt
    ```

- **Reload Environment**
  ```bash
  bash bootstrap.sh reload
  ```
  - Reloads the Vagrant environment.
  - Equivalent to:
    ```bash
    vagrant reload
    ```

- **Provision Environment**
  ```bash
  bash bootstrap.sh provision
  ```
  - Runs provisioning scripts such as `kubespray.sh` and other relevant setup scripts.

- **Check Environment Status**
  ```bash
  bash bootstrap.sh status
  ```
  - Displays the current status of the Vagrant environment.
  - Equivalent to:
    ```bash
    vagrant status
    ```

- **Save a Snapshot**
  ```bash
  bash bootstrap.sh save
  ```
  - Saves the current state of the environment as a snapshot.
  - Equivalent to:
    ```bash
    vagrant snapshot save xxx
    ```
    (Replace `xxx` with the desired snapshot name.)

- **Restore a Snapshot**
  ```bash
  bash bootstrap.sh restore <snapshot_name>
  ```
  - Restores the environment to a specified snapshot.
  - Equivalent to:
    ```bash
    vagrant snapshot restore <snapshot_name>
    ```

- **Delete a Snapshot**
  ```bash
  bash bootstrap.sh delete <snapshot_name>
  ```
  - Deletes a specified snapshot.
  - Equivalent to:
    ```bash
    vagrant snapshot delete <snapshot_name>
    ```

- **SSH into the Master Node**
  ```bash
  bash bootstrap.sh ssh
  ```
  - SSH into the Kubernetes master node in the Vagrant environment.
  - Equivalent to:
    ```bash
    vagrant ssh kube-master
    ```

- **Remove Environment**
  ```bash
  bash bootstrap.sh remove
  ```
  - Destroys the entire Vagrant environment forcefully.
  - Equivalent to:
    ```bash
    vagrant destroy -f
    ```

