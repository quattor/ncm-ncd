object template get-components-simple;

prefix "/software/components";

"acomponent/active" = true;
"acomponent/dependencies/pre" = list();
"acomponent/dependencies/post" = list();
"acomponent/dispatch" = true;
"adep/active" = true;
"adep/dependencies/pre/0" = "acomponent";
"adep/dependencies/post" = list();
"adep/dispatch" = true;

"aninactive/active" = false;
"aninvalid/noactiveset" = 0;
