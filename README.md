# DeRange

DeRange is a GUI utility which:
   * Tracks video media files in an XML database 
   * Normalizes and Compresses audio volume levels in video media files
   * stores user-defined tags, and creates tag-based XSPF playlists
   * plus a few other media file processing features.

DeRange V1 makes external calls to FFMPEG to do the actual crunching of the 
media data. It also relies on a handful of common external GNU utilities 
usually already present on most linux machines. DeRange V1 runs only under 
Linux because it is based on  Perl TK, and the TK widget set is linux only. 
A new port is in the pipeline, DeRange V2 is WX Widget-based and will be 
Windows Compatible using a Citrus Perl executable.

Although functional, DeRange V1 is not very refined, and contains a minimum 
of error trapping.

On the plus side:

   * Derange actually works, inherits the robustness of FFMPEG, and has 
   successfully processed thoudands of media files so far.
   
   * Although load times will increase, DeRange can manage tens of thousands 
   of media files in a single library. 
   
   * Stores tag metadata externally in its own database of XML files, and can 
   build XSPF playlists from these tags, with both include and exclude tags
   allowed. 
   
   * Multiple sequential playlists can be built, with the number being user-
   specified per-playlist.
   
   * Playlist content is pseudo-randomized, but sequential files in a folder 
   are preserved in order, so that they appear in order in playlists.

Where it needs improving:

   * Chokes if the directories and config files that it expects are not 
   present.
   
   * Chokes on invalid paths in config.
   
   * Does not know how to generate config files from scratch.

   * Can not rename files.
   
   * Can only manage one library root folder, would be a plus to switch  
   between multiple library root folders (video vs audio for example).

   * There is no reason why it should not be able to manage audio-only 
   files, but it hasn't been set up.
   
   * Does not know how to process webm media, probably other types.
   
