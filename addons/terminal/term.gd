tool
extends Control

var dir_path = '.'
var cmd_directory = ['ls', 'dir']
var history_loaded = false
var command_history = []
var history_file = 'user://.gdterm_history'
var history_enabled = false
var current_history_index = -1
var command_split = RegEx.new()
var pipe_file = 'user://.gdterm_pipe'
var cd = Directory.new()
var file = File.new()
var base_dir = "res://"
var sudo_args = []
var password_commands = ['sudo', 'git']
var help_full = """
intro:
	usage: intro [--help]
	--help			Show all help
godot:
	usage: godot [options] [path to scene or 'project.godot' file]
	-h, --help		Display full help message.
	Example:
		Run a scene on separated window:
			godot [options] path/to/scene/file.tscn [arguments]
shell commands:
	you can use shell commnads like:
		cd, ls, mkdir, chmod, echo, git, cat, etc...; into your godot project.
		pipes (|) with grep, awk, sed, etc...
navigation:
	←:				Back.
	→:				Forward.
	↑:				Prev command.
	↓:				Next command.
	history:		Show all executed commands.
	pwd:			Show current dir.
	reset:			Clean terminal.
theme:
	color:			change backgorund and foreground color
	Example:
		color ff000000 ffffffff  # ARGB format
		color back white  # X11 names format
	font:			change font attributes: font <size> [<outliner-size> [outliner-color]]
	Example with default values:
		font 12 0 white #color supported format

Terminal {version} - RKiemGames - MIT Licence
Report bugs: https://github.com/RKiemGames/godot-terminal-addons/issues
"""

func _ready():
	var config = ConfigFile.new()
	config.load('addons/terminal/plugin.cfg')
	var version = config.get_value('plugin', 'version')
	config = null
	help_full = help_full.replace('{version}', version)
	$Title.bbcode_text = $Title.bbcode_text.replace('{version}', version)
	$TextEdit.insert_text_at_cursor("")
	load_history()


func load_history():
	if file.file_exists(history_file):
		file.open(history_file, File.READ)
		var content = file.get_as_text()
		file.close()
		for cmd in content.split('\n', false):
			command_history.append(cmd)
		current_history_index = command_history.size()
	history_loaded = true


func _on_LineEdit_gui_input(event):
	if not history_loaded:
		load_history()
	if event is InputEventKey and event.scancode in [KEY_UP, KEY_DOWN] and command_history.size():
		history_enabled = true
		$HBoxContainer/LineEdit.disconnect("gui_input", self, "_on_LineEdit_gui_input")
		if event.scancode == KEY_UP and current_history_index > 0:
			current_history_index -= 1
		if event.scancode == KEY_DOWN and current_history_index < command_history.size() - 1:
			current_history_index += 1
		$HBoxContainer/LineEdit.text = command_history[current_history_index]
		$HBoxContainer/LineEdit.connect("gui_input", self, "_on_LineEdit_gui_input")
		$HBoxContainer/LineEdit.grab_focus()
	if event is InputEventKey and not event.scancode in [KEY_ENTER, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		history_enabled = false


func parse_command(text, pipe=false):
	command_split.compile('["\'][^"\']* +[^"\']*["\']')
	for g in command_split.search_all(text):
		var t = g.get_string()
		text = text.replace(t,t.replace(' ', '·'))
	var result = text.rsplit(' ', false)
	var command = result[0]
	var args = []
	result.remove(0)
	for a in result:
		if command == 'awk':
			a = a.replace('$', '\\$')
		a = a.replace("'", '').replace('"', '').replace('·', ' ')
		args.append(a)
	if pipe:
		file.open(pipe_file, File.READ)
		args.append(file.get_path_absolute())
		file.close()
	var output = []
	result = ""
	if command == 'intro':
		$Title.visible = true
		if '--help' in args:
			$Title.visible = false
			print_results(help_full)
		return
	var blocking = true
	if command == 'color':
		var bg = Color(args[0])
		var fg = Color(args[1])
		if not bg:
			bg = ColorN(args[0])
		if not fg:
			fg = ColorN(args[1])
		if fg == bg || fg == null:
			fg = bg.inverted()
		$Background.color = bg
		$TextEdit.modulate = fg
		$HBoxContainer.modulate = fg
		return
	if command == 'font':
		var fz = int(args[0])
		var foz = 0
		var foc = ColorN('white')
		if args.size() > 1:
			foz = int(args[1])
		if args.size() > 2:
			foc = Color(args[2])
			if not foc:
				foc = ColorN(args[2])
		var dynamic_font:DynamicFont = get_theme().default_font
		dynamic_font.size = fz
		dynamic_font.outline_size = foz
		dynamic_font.outline_color = foc
		dynamic_font.update_changes()
		return
	if command == 'git':
		if 'push' in args or 'publish' in args:
			var dargs = args
			var fargs = dargs.pop_front()
			if fargs == 'flow':
				dargs.pop_front()
				dargs.pop_front()
			var repo = 'origin'
			if dargs.size() > 1:
				var aux_args = []
				for a in dargs:
					if not a.begins_with('-'):
						break
					aux_args.append(a)
					dargs.pop_front()
				if dargs.size() > 1:
					repo = dargs[0]
					dargs.pop_front()
			OS.execute("git", ['remote', 'get-url', '--push', repo], true, output)
			var git_url = output[0]
			if not git_url.begins_with('git@'):
				var url = git_url.rsplit('//')[1]
				if '@' in url:
					var user = url.rsplit('@')[0]
					$Dialog/User.text = user
					git_url = git_url.replace('%s@' % user, '')
				$Dialog.set_meta('args', dargs)
				$Dialog.set_meta('git_url', git_url)
				open_dialog('git_push', true)
				return
			output = []
	if command == 'godot':
		command = OS.get_executable_path()
		if args:
			var gdfile = args[args.size() - 1]
			if '.tscn' in gdfile or '.godot' in gdfile:
				args[args.size() - 1]  = dir_path + '/' + gdfile
			blocking = ('--help' in args or '-h' in args)
		else:
			args = ['-e']
	if command == 'cd':
		var chdir = ''
		var current_dir = dir_path
		if args:
			chdir = args[0]
		if chdir:
			var dirs = (dir_path + '/' + chdir).split('/', false)
			var di = 0
			for d in dirs:
				if d == '..':
					dirs.remove(di)
					di -= 1
					if di >= 0:
						dirs.remove(di)
						di -= 1
				elif d == '.':
					dirs.remove(di)
					di -= 1
				di += 1
			dir_path = dirs.join('/')
			dirs = null
		else:
			dir_path = '.'
		if not dir_path:
			dir_path = '.'
		if not cd.dir_exists('res://%s' % dir_path):
			print_results('directory not exists: %s\n' % chdir)
			dir_path = current_dir
			return
		$HBoxContainer/Prompt.text = 'res://%s>' % dir_path.lstrip('.')
		return
	if command == 'pwd':
		print_results($HBoxContainer/Prompt.text.replace('>', ''))
		return
	if command == 'history':
		var l = 1
		for c in command_history:
			print_results("%s\t%s\n" % [str(l),c])
			l+=1
		return
	if command == 'sudo' and OS.get_name() != 'Windows':
		open_dialog(command)
		sudo_args = args
		return
	if command in cmd_directory:
		args.append(dir_path)
	if command == 'start' and not '/?' in args:
		blocking = false
	OS.execute(command, args, blocking, output, true)
	if not blocking:
		return
	for l in output:
		result += l
	if command in ['reset', 'clear', 'cls']:
		$TextEdit.text = ""
		return
	return result


func open_dialog(command, username=false):
	var height = 32
	$Dialog/Password.margin_top = -12
	$Dialog/User.visible = false
	$Dialog.set_meta('command', command)
	if username:
		height = 64
		$Dialog/Password.margin_top = 3
		$Dialog/User.visible = true
	$Dialog/Password.text = ""
	$Dialog.popup_centered(Vector2(330,height))
	$Dialog/Password.grab_focus()


func print_results(result):
	$TextEdit.cursor_set_line($TextEdit.get_line_count() - 1)
	$TextEdit.cursor_set_column(0)
	$TextEdit.insert_text_at_cursor("%s" % result)
	$TextEdit.clear_undo_history()


func update_history(text):
	if history_enabled:
		return
	command_history.append(text)
	var file = File.new()
	var mode = File.READ_WRITE
	if not file.file_exists(history_file):
		mode = File.WRITE
	file.open(history_file, mode)
	file.seek_end()
	file.store_string(text + '\n')
	file.close()


func enter_text(new_text):
	$Title.visible = false
	update_history(new_text)
	current_history_index = command_history.size()
	var pipe_command = new_text.split('|')
	var result = null
	$HBoxContainer/LineEdit.text = ""
	if pipe_command.size() > 1:
		var f = File.new()
		var array_cmd = []
		for cmd in pipe_command:
			array_cmd.append(cmd.lstrip(' ').rstrip(' '))
		var first = array_cmd.pop_front()
		result = parse_command(first)
		f.open(pipe_file, File.WRITE)
		f.store_string(result)
		f.close()
		for cmd in array_cmd:
			result = parse_command(cmd, true)
			cd.remove(pipe_file)
			f.open(pipe_file, File.WRITE)
			f.store_string(result)
			f.close()
		cd.remove(pipe_file)
		print_results(result)
		return
	result = parse_command(new_text)
	if result:
		print_results(result)


func _on_LineEdit_text_entered(new_text):
	enter_text(new_text)


func _on_Title_gui_input(event):
	$HBoxContainer/LineEdit.grab_focus()


func _on_TextEdit_gui_input(event):
	$HBoxContainer/LineEdit.grab_focus()


func _on_git_push(password):
	var git_url = $Dialog.get_meta('git_url').rsplit('//')
	var args = $Dialog.get_meta('args')
	var prefix = git_url[0]
	var repo = git_url[1].replace('\n','')
	var user = $Dialog/User.text
	var output = []
	password = HTTPClient.new().query_string_from_dict({u=password}).replace('u=', '')
	$Dialog.visible = false
	yield(get_tree().create_timer(0.034), 'timeout')
	OS.execute('git', ['push', '%s//%s:%s@%s' % [prefix, user, password, repo]] + args, true, output, true)
	for o in output:
		print_results(o.replace(':%s' % password, ':*****'))
		o = null
	output = []


func _on_sudo(password):
	var output = []
	var base_args = ['SUDO_PASS=%s' % password, 'SUDO_ASKPASS=addons/terminal/pass.sh','sudo', '-A']
	$Dialog.visible = false
	yield(get_tree().create_timer(0.034), 'timeout')
	OS.execute('env', base_args + sudo_args, true, output, false)
	for o in output:
		print_results(o)
		o = null


func _on_Password_text_entered(password):
	call('_on_%s' % $Dialog.get_meta('command'), password)
