extends Reference
var api
var trainer
func on_load(context):
    api = context
    trainer = preload("res://ftc_mods/ftc.trainer/Trainer.gd").new()
    trainer.mod_api = api
    trainer.SETTINGS = api.config_path()
    # Import preferences once; existing loose trainer files remain usable.
    var previous = OS.get_executable_path().get_base_dir().plus_file("mods/single_player_trainer/settings.cfg")
    var file = File.new()
    if not file.file_exists(trainer.SETTINGS) and file.file_exists(previous):
        Directory.new().copy(previous, trainer.SETTINGS)
    if api.add_root("FtcSinglePlayerTrainer", trainer) == null:
        return false
    api.provide_service("trainer", trainer)
    return true
func on_unload():
    if is_instance_valid(trainer):
        trainer.reset_all()
