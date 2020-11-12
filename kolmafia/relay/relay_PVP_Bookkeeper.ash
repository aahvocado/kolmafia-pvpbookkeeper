import <pvpBookkeeper.ash>

void main(){
	write("<html><body>");
	write(greeting());
	write("<form><input type=\"text\" name=\"fightCount\" /><input type=\"submit\" value=\"This many fights!\"/></form>");
	int myMax=to_int(form_field("fightCount"));

	setCompact();
	writeln(doMaths(myMax));
	writeln(renderMatchups());
	writeln(formatResults());
	writeln(formatSummary());

	writeln("<p><a href=\"peevpee.php\">Back to the Colosseum</a></p>");
	write("</body></html>");
}
