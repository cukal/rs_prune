# rs_prune.sh

Script to check & prune a xsitools/xsibackup area.

### Prerequisites

XSIBackup with xsitools deduplicated backup area.
XSIBackups are taken with these options that control the backup directory naming:
```
--backup-point="<your backup location>/$(date +%Y%m'00000000')"
```
This generates backup directory structures such as:


### Installing

Copy the script on ESX & make it executable.

## Authors

* **rs** - *Initial work* - [rs](https://33hops.com/forum/profile.php?id=186)

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details

## Acknowledgments
XSIBackup for an excellent ESX software!
