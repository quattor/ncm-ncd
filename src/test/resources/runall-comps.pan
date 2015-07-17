object template runall-comps;

prefix "/software/components";

"acomponent/active" = true;
"acomponent/dependencies/pre" = list();
"acomponent/dependencies/post" = list();
"acomponent/dispatch"  = true;

"anotherone/active" = true;
"anotherone/dependencies/pre" = list("acomponent");
"anotherone/dependencies/post" = list();
"anotherone/dispatch"  = true;

"yetonemore/active" = true;
"yetonemore/dependencies/pre" = list();
"yetonemore/dependencies/post" = list("anotherone");
"yetonemore/dispatch" = true;
