from ...src.backup_reinit import purge_configs


def main() -> None:
    """Purges instantaneous project configurations.

    Removes all existing configurations for a current project, in order to clean out
    directories so to work on a different project.
    """

    purge_configs()


if __name__ == "__main__":
    main()
