tool
extends Control

var dir_path = '.'
var cmd_directory = ['ls', 'dir']
var command_history = []
var history_file = '.history'
var history_enabled = false
var current_history_index = -1
var command_split = RegEx.new()
var pipe_file = '.gdterm_pipe'
var cd = Directory.new()
var base_dir = "res://"
var sudo_args = []
var help_full = """
help:
	usage: help [--all]
	--all			Show all help
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

Terminal 1.0 - RKiemGames - MIT Licence
Report bugs to rkiemgames@gmail.com
"""


func _ready():
	$TextEdit.insert_text_at_cursor("")
	var file = File.new()
	if file.file_exists(history_file):
		file.open(history_file, File.READ)
		var content = file.get_as_text()
		file.close()
		for cmd in content.split('\n', false):
			command_history.append(cmd)
		current_history_index = command_history.size()


func _on_LineEdit_gui_input(event):
	if event is InputEventKey and event.scancode in [KEY_UP, KEY_DOWN] and command_history.size():
		prints(command_history)
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
		args.append(pipe_file)
	var output = []
	result = ""
	if command == 'help':
		$Title.visible = true
		if '--all' in args:
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
		var dirs = dir_path.split('/', true)
		if chdir:
			var back_dir = chdir.split('/', false)
			back_dir.invert()
			for d in back_dir:
				if d == '..' and dirs.size():
					dirs.remove(dirs.size() - 1)
				elif d == '.' or dirs.size() == 0:
					continue
				else:
					dirs.append(d)
			back_dir = null
			dir_path = dirs.join('/')
		else:
			dir_path = '.'
		if not cd.dir_exists('res://%s' % dir_path):
			print_results('directory not exists: %s' % chdir)
			dir_path = current_dir
			return
		$HBoxContainer/Prompt.text = 'res://%s>' % dir_path.replace('.', '')
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
	if command == 'sudo':
		$Dialog/Password.text = ""
		$Dialog.popup_centered(Vector2(330,24))
		$Dialog/Password.grab_focus()
		sudo_args = args
		return
	if command in cmd_directory:
		args.append(dir_path)
	OS.execute(command, args, blocking, output, true)
	if not blocking:
		return
	for l in output:
		result += l
	if command in ['reset', 'clear', 'cls']:
		$TextEdit.text = ""
		return
	return result


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
			OS.execute('rm', [pipe_file], true, [], true)
			f.open(pipe_file, File.WRITE)
			f.store_string(result)
			f.close()
		OS.execute('rm', [pipe_file], true, [], true)
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


func _on_Password_text_entered(new_text):
	var output = []
	$Dialog.visible = false
	print_results("running...")
	yield(get_tree().create_timer(1), 'timeout')
	var base_args = ['SUDO_PASS=%s' % new_text, 'SUDO_ASKPASS=addons/terminal/pass.sh','sudo', '-A']
	OS.execute('env', base_args + sudo_args, true, output, false)
	for o in output:
		print_results(o)
	
