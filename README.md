Rails Autocomplete Generator Plugin
==================================

### Warning:: Mac OS ONLY!!

Quick hit plugin to generate autocompletes for your Rails project's class names and public methods.

### Installation & Configuration

1. Clone this into the Packages folder in your ~/Library/Application Support/Sublime folder.  
2. Hit [Cmd+k, Cmd+p] - this will try to generate the autocomplete file but will most likely do nothing except add the "autocomplete_settings" key to your sublime-project file.
3. Open up your project file:
  * [Cmd+p] and type 'Open Project File', or  
  * Hit [Cmd+,, Cmd+p], or  
  * Project settings file under 'Preferences/Package Settings/Rails Autocomplete/Open Project Settings'
4. Set the content of these keys:
  * ruby_path  
    The full path to the ruby or rvm ruby that is needed to parse the project files.  
  * source_paths  
    A comma separate list of the folders that you want parsed and added to the autocomplete file.  
    At a minimum this needs to be set.  
  * exclude_paths  
    A comma separate list of the sub-folders of the source_paths that you want excluded.  
  * exclude_class_names & exclude_class_regex  
    Use one (string match or regex match) or both to exclude found class names.  
  * exclude_method_names & exclude_method_regex  
    Use one (string match or regex match) or both to exclude found method names.  

5. Save the project file
6. Hit [Cmd+k, Cmd+p] again.

### Usage

Open one of your Rails projects and then a file in that project.  
Hit [Cmd+k, Cmd+p].  
Now you should have your class / module names and method names show up in your autocomplete dropdown.

NOTE: Sublime is supposed to reload the regenerated autocomplete file, but it doesn't at times. In such cases, close and reopen Sublime.

