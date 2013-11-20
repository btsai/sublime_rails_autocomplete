# Sublime API reference: https://www.sublimetext.com/docs/3/api_reference.html
import sublime, sublime_plugin
import os, subprocess, threading, pipes, json, time

# this monitors for the file save callback.
# if there is a project folder AND the generation script exists (/scripts/sublime/generate_sublime_snippets.rb),
# it will kick off the generation script in a separate thread
# (no need to wait for it to complete, Sublime will automatically reload the sublime-completions folder in the background).
class AutocompleteEventListener(sublime_plugin.EventListener):

	generator_thread = None

	def on_post_save(self, view):
		# don't bother doing anything if there is no project folder
		settings = AutocompleteSettings(view.window())
		settings.clear_autocomplete_file()
		if not settings.ready_for_autocomplete():
			return

		if self.generator_thread != None:
			self.generator_thread.stop()
		self.generator_thread = AutocompleteBackgroundGenerator(settings)
		self.generator_thread.start()

# end AutocompleteEventListener

# this is the separate thread class that runs the autocomplete generator in the background.
class AutocompleteBackgroundGenerator(threading.Thread):
	def __init__(self, settings):
		self.timeout = 5
		self.settings = settings
		threading.Thread.__init__(self)


	def run(self):
		# use the package's ruby generation script.
		# save as a default generic name so that the autocomplete file is always generated on the fly for each rails project.
		# this is to avoid having autocompletes from one project bleeding into another.

		started = time.time()
		print("> Running Rails autocomplete generation...")

		json_settings = json.dumps(self.settings.settings)
		args = [
			self.settings.ruby_path,								# which ruby to execute (defaults to ruby but can be set on per project basis)
			self.settings.script_path(),						# path of the ruby script to run
			json_settings,													# autocomplete settings in json format
			self.settings.autocomplete_filepath(),	# filepath for output; saving is done on the ruby side
			self.settings.project_folder
		]
		result = subprocess.check_output(args,
			                               cwd=self.settings.project_folder,
			                               stderr=subprocess.STDOUT,
			                               shell=False)
		# return the ruby results to the sublime console
		result = result.decode('utf8')

		print(result)
		print("> Completed in %.3fs." % (time.time() - started) )
		if 'ERROR:' in result:
			sublime.error_message(result)


	def stop(self):
		if self.isAlive():
			self._Thread__stop()

# end AutocompleteBackgroundGenerator

class AutocompleteSettings:
	def __init__(self, window):
		self.window = window
		self.project_folder = None if len(window.folders()) == 0 else window.folders()[0]
		self.enabled = False
		self.has_source_paths = False
		self.settings = sublime.load_settings(self.settings_filename)

		# if there is a project folder, then get the settings
		if self.project_folder:
			self.project_filepath = window.project_file_name()
			self.get_autocomplete_settings()
			self.project_name = os.path.basename(self.project_folder)

	@property
	def project_folder_exists(self):
		return self.project_folder != None

	@property
	def project_settings_key(self):
		return 'autocomplete_settings'

	@property
	def settings_filename(self):
		return 'RailsAutocomplete.sublime-settings'

	@property
	def current_project(self):
		return self.settings.get('current_project')

	@current_project.setter
	def current_project(self, value):
		self.settings.set('current_project', value)
		sublime.save_settings(self.settings_filename)


	def get_autocomplete_settings(self):
		self.settings = self.ensure_project_settings_has_autocomplete_settings()

		# give some feedback about the settings
		if len(self.settings['source_paths']) == 0:
			sublime.status_message('You need to set the source paths in the RailsAutocomplete setting.')

		# map some values to this object
		self.enabled = self.settings['enabled']
		self.has_source_paths = (len(self.settings['source_paths']) > 0)
		self.ruby_path = self.settings['ruby_path']


	def ensure_project_settings_has_autocomplete_settings(self):
		settings = self.window.project_data()
		if self.project_settings_key in settings:
			# ensure that all keys have a default, in case something got deleted, by merging with the default settings.
			# any existing settings will win.
			full_settings = dict( list(self.default_settings.items()) + list(settings[self.project_settings_key].items()) )

			# save back to project settings if there are changes
			if settings[self.project_settings_key] != full_settings:
				sublime.status_message("Updated project settings.")
				self.window.set_project_data(settings)
		else:
			# not set up yet, so add the autocomplete settings node to the project settings
			settings[self.project_settings_key] = self.default_settings
			self.window.set_project_data(settings)

			# show the project file and intro information
			sublime.run_command('open_project_file')
			self.window.open_file(os.path.join(self.base_path, 'intro.txt'))

		return settings[self.project_settings_key]


	def ready_for_autocomplete(self):
		return (self.project_folder_exists and self.enabled and self.has_source_paths)


	@property
	def default_settings(self):
		return {
			'ruby_path': 'ruby',
			'enabled': True,				# note Python style 'true', converts to true when viewing in settings viewer as JSON
			'source_paths': [],
			'exclude_paths': [],
			'exclude_class_names':
				['ClassMethods', 'InstanceMethods'],
			'exclude_method_names':
				['<=>'],
			'exclude_class_regex': '',
			'exclude_method_regex': ''
		}

	@property
	def base_path(self):
		return os.path.join(sublime.packages_path(), 'RailsAutocomplete')

	# sublime doesn't have project scope (!!), so we need to use a common name so that
	# we don't have one project's autocomplete show up in another.
	def autocomplete_filepath(self):
	 	return os.path.join(sublime.packages_path(), 'User', 'rails_project.sublime-completions')


	def script_path(self):
		return os.path.join(self.base_path, 'generate_sublime_snippets.rb')


	def clear_autocomplete_file(self):
		if os.path.exists(self.autocomplete_filepath()):
			os.remove(self.autocomplete_filepath())

# end AutocompleteSettings

# utility commands for this plugin
class OpenProjectFileCommand(sublime_plugin.WindowCommand):
    def run(self):
    	project_file = self.window.project_file_name()
    	if project_file:
    		self.window.open_file(project_file)

# end OpenProjectFileCommand

class OpenAutocompleteFileCommand(sublime_plugin.WindowCommand):
    def run(self):
    	autocomplete_file = AutocompleteSettings(self.window).autocomplete_filepath()
    	if os.path.exists(autocomplete_file):
    		self.window.open_file(autocomplete_file)

# end OpenProjectFileCommand

