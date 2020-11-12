/*
	Updated to handle Season 34 minis, per this post:
	http://kolmafia.us/showthread.php?10762-Vhaeraun-s-Glorious-PVP-Bookkeeper&p=145231&viewfull=1#post145231
*/
notify dextrial;

string viewPattern = "a href\=\"(peevpee\.php\\?action\=log.*?lid\=(\\d+).*?)\".*?m</small></td><td><small>(.*?)</small>";
string playersPattern;
string contestPattern;
string fitePattern;
boolean compact;
// string INFO_BOOTH_REGEX = '<td valign="top" nowrap><b>(.*?)(?:\\**|&Dagger;)</b></td><td valign="top">(.*?)</td><td.*?</td>';
string INFO_BOOTH_REGEX = "<td valign=\"top\".*?><b>(.*?)(?:\\**|&Dagger;)</b></td><td valign=\"top\">(.*?)</td><td.*?(\\d+,*\\d*)+</td><td.*?(\\d+,*\\d*)+</td>";
string marginPattern = ".*?(\\d+%*).*?";
string swaggerPattern = "([+-]\\d+)&nbsp;Swagger";
string famePattern = "([+-]\\d+)&nbsp;Fame";
string flowerPattern = "([+-]\\d+)&nbsp;Flower";
string FIGHT_REPLAY_REGEX = "(?<=Fight Replay: )(19[0-9]{2}|[2][0-9][0-9]{2})(?:-)([012][1-9]|[012][0-9]|3[01])(?:-)(0?[1-9]|1[12])";
string myName = my_name();

int majorVersion=1;
int minorVersion=8;

string versionCheck(){
	string lastChecked = get_property("pvpBookkeeper.versionLastChecked");
	string results ="Version " +majorVersion+"."+minorVersion;
	if(today_to_string() != lastChecked){
		string url = "http://kolmafia.us/showthread.php?t=10762-Vhaeraun-s-Glorious-PVP-Bookkeeper";
		string currentThread = visit_url(url);

		string versionPattern = "<font size=\"5\">.*?Version (\\d+).(\\d+)<br />.*?Vhaeraun's Glorious PVP Bookkeeper</font>";
		matcher versionMatcher = create_matcher(versionPattern, currentThread);

		if(versionMatcher.find()){
			int latestMajorVersion= to_int(group(versionMatcher,1));
			int latestMinorVersion= to_int(group(versionMatcher,2));
			if(latestMinorVersion != minorVersion || latestMajorVersion != majorVersion){
				results="<font color=\"red\"><a href=\""+url+"\">Your script is not up to date!</a></font>";
			}
		}
		else{
			results="<b>Could not determine whether "+majorVersion+"."+minorVersion+  " is the latest version.</b>";
		}
	}
	set_property("pvpBookkeeper.versionLastChecked",today_to_string());
	return '<b>' + results + '</b></br>';
}

int max;
string [int] TitleIndex;

record ColorPair{
	int percentage;
	string color;
};

ColorPair [int] myColors;
// sorry one day I'll also let you support custom colors
ColorPair [int] matchUpColors;
matchUpColors[0].percentage=0;
matchUpColors[0].color="#6b3128";
matchUpColors[1].percentage=10;
matchUpColors[1].color="#98473a";
matchUpColors[2].percentage=50;
matchUpColors[2].color="#9c7246";
matchUpColors[3].percentage=70;
matchUpColors[3].color="#928843";
matchUpColors[4].percentage=90;
matchUpColors[4].color="#8baf44";
matchUpColors[5].percentage=100;
matchUpColors[5].color="#54af44";

matchUpColors[6].percentage = 101; // n/a cell color
matchUpColors[6].color="#949a9c";
matchUpColors[7].percentage = 102; // data cell
matchUpColors[7].color="#f8fafb";
// -- score tracking
int [int] currentScore;
int [int] currentScoreHC;
// --
record OneRound {
	int offense;
	int oWins;
	int defense;
	int dWins;
};
record StorageRound{
	int mini;
	int win;
	string margin;
};
// --
record TotalStats{
	int swagger;
	int fame;
	int winningness;
	int flowers;
	OneRound [string] contests;
};
TotalStats summary;
// --
record StorageFight{
	string date;
	string opponentName;
	int offense;
	int attackerWon;
	StorageRound [7] a;
};
StorageFight [string] ProcessedRecords;
// --
record MinigameHistory {
	int mini;
	int total;
	int wins;
	int losses;
	string margin;
};
record Matchup {
	string opponentName;
	MinigameHistory [int] history;
	int totalMatched;
	int winsMatched;
	int lossesMatched;
	string lastmatch;
	int [int] mostRecent;
};
// WARNING: the key is supposed to be the name string, but when sorting,
// the key stays in place while the values are sorted - I need to fix that sometime
Matchup[string] processedMatchups;

// -- functions start
string visitInformationBooth(){
	string informationBooth = visit_url("peevpee.php?place=rules");

	// minigame rules
	matcher contestMatcher = create_matcher(INFO_BOOTH_REGEX, informationBooth);
	int index=0;
	// print("visitInformationBooth()" + informationBooth);
	while(contestMatcher.find()){
		string roundText = group(contestMatcher, 1).entity_decode();
		if (roundText != "Purrrity") {
		    roundText = replace_string(roundText, "rrr", "r");
		}
		TitleIndex[index]=roundText;

		// cache current score
		currentScore[index] = group(contestMatcher, 3).to_int();
		currentScoreHC[index] = group(contestMatcher, 4).to_int();
		// print("SC: " + group(contestMatcher, 3));
		// print("HC: " + group(contestMatcher, 4));

		// print(index + ": " + roundText);
		index=1+index;
	}
	TitleIndex[index] = "Whole Fights"; // last column


	matcher seasonMatcher = create_matcher("<b>Current Season: </b>(\\d+)",informationBooth);
	seasonMatcher.find();
	return group(seasonMatcher,1);
}
MinigameHistory getMinigameTotals(Matchup matchupData) {
	MinigameHistory totalHistory;
	foreach idx, minigame in matchupData.history {
		totalHistory.total += minigame.total;
		totalHistory.wins += minigame.wins;
		totalHistory.losses += minigame.losses;
	}

	return totalHistory;
}
int get_matchup_win_rate(Matchup matchupData) {
	return truncate((to_float(matchupData.winsMatched)/matchupData.totalMatched) * 100);
}
int get_sort_value(Matchup matchupData) {
	int date = matchupData.lastmatch.to_int();
	int winRate = get_matchup_win_rate(matchupData); // high winrate = later in list
	if (winRate >= 100) {
		winRate = 1000; // hacky way to force 100% wins towards the bottom of the list
	}

	int totalMatchesValue = matchupData.totalMatched * -100; // more matches = earlier in list
	if (matchupData.totalMatched == 1) {
		totalMatchesValue = 1000; // force matches that have only occured once to the bttom
	}

	return totalMatchesValue + winRate;
}
int lookupIndex(string name){
	int returnValue = -1;
	foreach key in titleIndex{
		string lookupname = name;
		if (lookupname != "Purrrity") {
		    lookupname = replace_string(lookupname, "rrr", "r");
		}
		if(titleIndex[key]≈lookupname){
			returnValue = key;
		}
	}
	return returnValue;
}
string lookupName(int index){
	string returnValue="";
	foreach key in titleIndex{
		if(key==index){
			returnValue = titleIndex[key];
		}
	}
	return returnValue;
}
string getArchive(){
  string pvp_url = "peevpee.php?place=logs&mevs=0&oldseason=0&showmore=1";
  string pvpArchive = visit_url(pvp_url);

  return pvpArchive;
}
StorageFight evaluateFightCompact(string url, int idx){
	StorageFight thisFight;
	string myFight = visit_url(url);
	matcher playersMatcher = create_matcher(playersPattern, myFight);

	playersMatcher.find();
	string attacker = group(playersMatcher, 1);
	string defender = group(playersMatcher, 2);
	print("Processing Fight " + idx + ": " + attacker + " vs " + defender);

	matcher contestMatcher = create_matcher(contestPattern,myFight);
	matcher fiteMatcher = create_matcher(fitePattern,myFight);

	matcher replayMatcher = create_matcher(FIGHT_REPLAY_REGEX, myFight);
	boolean didFind = replayMatcher.find();
	if (didFind && replayMatcher.group_count() >= 3) {
		thisFight.date = replayMatcher.group(1) + replayMatcher.group(2) + replayMatcher.group(3);
	}

	if(attacker≈myName){
		thisFight.offense=1;
		thisFight.opponentName = defender;

	} else {
		thisFight.opponentName = attacker;
	}

	int arrayIndex=0;
	while(contestMatcher.find()){
		string title = group(contestMatcher,1).entity_decode();
		string contestWinner = group(contestMatcher, 2);

		int internalId = lookupIndex(title);

		StorageRound thisRound;
		thisRound.mini = internalId;

		if(contestWinner≈myName){
			thisRound.win=1;
		}


		thisFight.a[arrayIndex] = thisRound;
		string detailText = group(contestMatcher, 3);
		matcher marginMatcher=create_matcher(marginPattern,detailText);


		if(marginMatcher.find()){
			thisRound.margin=group(marginMatcher,1);
		}

		arrayIndex=arrayIndex+1;
	}
	if (fiteMatcher.find()){
		string fiteWinner = group(fiteMatcher,1);
		if (fiteWinner≈attacker){
			thisFight.attackerWon = 1;
		}
	}

	return thisFight;
}
StorageFight evaluateFightFull(string url, int idx){
	StorageFight thisFight;
	string myFight = visit_url(url);

	matcher playersMatcher = create_matcher(playersPattern, myFight);
	playersMatcher.find();
	string attacker = group(playersMatcher, 1);
	string defender = group(playersMatcher,2);
	print("Processing Fight " + idx + ": " + attacker + " vs " + defender);

	matcher contestMatcher = create_matcher(contestPattern,myFight);
	matcher fiteMatcher = create_matcher(fitePattern,myFight);

	matcher replayMatcher = create_matcher(FIGHT_REPLAY_REGEX, myFight);
	boolean didFind = replayMatcher.find();
	if (didFind && replayMatcher.group_count() >= 3) {
		// print(replayMatcher.group(1) + "/" + replayMatcher.group(2) + "/" + replayMatcher.group(3));
		thisFight.date = replayMatcher.group(1) + replayMatcher.group(2) + replayMatcher.group(3);
	}

	if(attacker≈myName){
		thisFight.offense=1;
		thisFight.opponentName = defender;

	} else {
		thisFight.opponentName = attacker;
	}

	int arrayIndex=0;
	while(contestMatcher.find()){
		string title = group(contestMatcher,2).entity_decode();

		string contestWinner;
		if(group(contestMatcher,1)==""){
			contestWinner=defender;
		}
		else{
			contestWinner=attacker;
		}

		int internalId = lookupIndex(title);

		StorageRound thisRound;
		thisRound.mini = internalId;

		if(contestWinner≈myName){
			thisRound.win=1;
		}

		thisFight.a[arrayIndex] = thisRound;
		string detailText = group(contestMatcher, 3);
		matcher marginMatcher=create_matcher(marginPattern,detailText);

		if(marginMatcher.find()){
			thisRound.margin=group(marginMatcher,1);
		}

		arrayIndex=arrayIndex+1;
	}
	if (fiteMatcher.find()){
		string fiteWinner = group(fiteMatcher,1);
		if (fiteWinner≈attacker){
			thisFight.attackerWon = 1;
		}
	}

	return thisFight;
}
void evaluateProcessedFight(StorageFight thisFight){
	StorageRound [int] theRounds = thisFight.a;

	int contestWins;

	boolean offense = (thisFight.offense==1);
	foreach key in theRounds{
		StorageRound thisRound = theRounds[key];

		string title = lookupName(thisRound.mini);
		OneRound thisContest = summary.contests[title];
		contestWins=contestWins + thisRound.win;
		if(offense){
			summary.contests[title].offense=1+summary.contests[title].offense;
			summary.contests[title].oWins=summary.contests[title].oWins + thisRound.win;
		}
		else{
			summary.contests[title].defense=1+summary.contests[title].defense;
			summary.contests[title].dWins=summary.contests[title].dWins + thisRound.win;
		}
	}

	if(offense){
		summary.contests["Whole Fights"].offense=summary.contests["Whole Fights"].offense+1;
		if(thisFight.attackerWon>0){
			summary.winningness = summary.winningness+1;
			summary.contests["Whole Fights"].oWins=summary.contests["Whole Fights"].oWins+1;
		}
		else{
			summary.winningness = summary.winningness-1;
		}
	}
	else{
		summary.contests["Whole Fights"].defense=summary.contests["Whole Fights"].defense+1;
		if(thisFight.attackerWon==0){
			summary.contests["Whole Fights"].dWins=summary.contests["Whole Fights"].dWins+1;
		}
		else{
			summary.winningness = summary.winningness-1;
		}
	}
}
Matchup evaluateMatchup(StorageFight thisFight){
	string opponentName = thisFight.opponentName;
	Matchup thisMatchup;
	MinigameHistory [int] thisHistory;
	int minigamesWon = 0;
	int minigamesLost = 0;

	// never tracked this opponent before? build new history
	if(!(processedMatchups contains opponentName)){
		foreach key in TitleIndex {
			// print("TitleIndex.key: " + key);
			MinigameHistory newHistory;
			newHistory.mini = key;
			newHistory.total = 0;
			newHistory.wins = 0;
			newHistory.losses = 0;

			thisHistory[key] = newHistory;

			if (TitleIndex[key] != 'Whole Fights') { // ignore totals column
				thisMatchup.mostRecent[key] = 0;
			}
		}

	// existing matchup
	} else {
		thisMatchup = processedMatchups[opponentName];
		thisHistory = thisMatchup.history;
	}

	// update the history with current fight
	foreach idx in thisFight.a {
		StorageRound thisRound = thisFight.a[idx];
		int miniKey = thisRound.mini;
		string thisTitle = TitleIndex[miniKey];

		MinigameHistory miniHistory = thisHistory[miniKey];
		miniHistory.margin = thisRound.margin;
		miniHistory.total += 1;
		if (thisRound.win == 1) {
			miniHistory.wins += 1;
			minigamesWon += 1;

			if (thisMatchup.mostRecent[miniKey] == 0) {
				thisMatchup.mostRecent[miniKey] = 1;
			}

		} else {
			miniHistory.losses += 1;
			minigamesLost += 1;

			if (thisMatchup.mostRecent[miniKey] == 0) {
				thisMatchup.mostRecent[miniKey] = -1;
			}
		}
	}

	// update win/loss
	if (minigamesWon > minigamesLost) {
		thisMatchup.winsMatched += 1;
	} else {
		thisMatchup.lossesMatched += 1;
	}

	thisMatchup.lastmatch = thisFight.date;
	thisMatchup.opponentName = opponentName;
	thisMatchup.totalMatched += 1;
	thisMatchup.history = thisHistory; // reupdate history
	processedMatchups[opponentName] = thisMatchup; // add matchup to cache
	return thisMatchup;
}
void readPreviousResults(string file){
	file_to_map(file, processedRecords);
	file_to_map("pvpColors.txt", myColors);
	if(myColors[0].color==""){
		myColors[0].percentage=0;
		myColors[0].color="#FF0000";
		myColors[1].percentage=50;
		myColors[1].color="#EF7500";
		myColors[2].percentage=70;
		myColors[2].color="#000080";
		myColors[3].percentage=90;
		myColors[3].color="#007000";
		myColors[4].percentage=100;
		myColors[4].color="black";
	}
}
void saveResults(string file){
	map_to_file(processedRecords, file);
	// map_to_file(myColors,"pvpColors.txt");
}
int swaggerGained(string fight){
	int swagger;
	matcher swaggerMatcher = create_matcher(swaggerPattern,fight);

	if(swaggerMatcher.find()){
		swagger = to_int(group(swaggerMatcher, 1));
	}
	return swagger;
}
int flowersPicked(string fight){
	int flower;
	matcher flowerMatcher = create_matcher(flowerPattern,fight);

	if(flowerMatcher.find()){
		flower = to_int(group(flowerMatcher, 1));
	}
	return flower;
}
int fameTaken(string fight){
	int fame;
	matcher fameMatcher = create_matcher(famePattern, fight);
	if(fameMatcher.find()){
		fame = to_int(group(fameMatcher,1));
	}
	return fame;
}
// -- render methods
string wrapTD(string input, float percentage){
	string color=myColors[0].color;
	foreach key in myColors{
		if(percentage >= myColors[key].percentage){
			color=myColors[key].color;
		}
	}

	string wrapped = "<td><font color=\""+color+"\">" +input + "</font></td>";
	return wrapped;
}
string wrapTDMatchup(string input, float percentage){
	string color = matchUpColors[0].color;
	foreach key in matchUpColors{
		if(percentage >= matchUpColors[key].percentage){
			color = matchUpColors[key].color;
		}
	}

	string fontcolor = 'white';
	if (percentage == 102) {
		fontcolor = 'black';
	}

	string wrapped = '<td style="background-color: ' + color + '; color: ' + fontcolor + '; text-align: center;">' + input + '</td>';
	return wrapped;
}
string wrapTDMatchup(string input){
	return wrapTDMatchup(input, 102);
}
string wrapTD(string s){
	return '<td><font style="font-size: 13px; color: black;">' + s + '</font></td>';
}
string wrapTR(string input){
	string wrapped = "<tr>" +input + "</tr>";
	return wrapped;
}
string createMatchupCell(int winString, int lossString, int ratio, boolean hasRecentVictory) {
	string winsStyle = hasRecentVictory ? "font-size: 15px; font-weight: 800;" : "font-size: 13px;";
	string lossStyle = !hasRecentVictory ? "font-size: 15px; font-weight: 800;" : "font-size: 13px;";

	string subHtml = '';
	subHtml += '<font style="' + winsStyle + '">' + winString + '</font>';
	subHtml += ':';
	subHtml += '<font style="' + lossStyle + '">' + lossString + '</font>';
	subHtml += '<br/>';
	subHtml += '<font style="font-size: 11px">(' + ratio + '%)</font>';

	return wrapTDMatchup(subHtml, ratio);
}
string createMatchupCell(int winString, int lossString, int ratio) {
	string winsStyle = "font-size: 13px;";
	string lossStyle = "font-size: 13px;";

	string subHtml = '';
	subHtml += '<font style="' + winsStyle + '">' + winString + '</font>';
	subHtml += ':';
	subHtml += '<font style="' + lossStyle + '">' + lossString + '</font>';
	subHtml += '<br/>';
	subHtml += '<font style="font-size: 11px">(' + ratio + '%)</font>';

	return wrapTDMatchup(subHtml, ratio);
}
string formatSummary(){
	string html = "<table style='margin-top: 10px;' border='1' cellspacing='1'><tbody>";
	string header = "<tr style='font-size: 12px;'>";
	header += "<th></th>";
	header += "<th colspan='1'>Total</th>";
	header += "<th colspan='1'>Average</th>";
	header += "</tr>";
	html += header;

	OneRound totals = summary.contests["Whole Fights"];

	float avgFlowers;
	float avgSwagger;
	if(totals.offense>0){
		avgFlowers = round(100.0 * summary.flowers/to_float(totals.offense))/100.0;
		avgSwagger = round(100.0 *summary.swagger/to_float(totals.offense))/100.0;
	}
	float avgFame = round(100.0 * summary.fame/(totals.offense +totals.defense))/100.0;
	float avgWinningness;
	if(totals.offense>0){
		float avgWinningness = round(100.0 * summary.winningness/(totals.offense))/100.0;
	}

	html = html + wrapTR(wrapTD("Fame gain")+wrapTDMatchup(summary.fame)+wrapTDMatchup(avgFame));
	if(totals.offense>0){
		html = html + wrapTR(wrapTD("Winningness") + wrapTDMatchup(summary.winningness) + wrapTDMatchup(avgWinningness));
		html = html + wrapTR(wrapTD("-")+wrapTD("-")+wrapTD("Offense Avg."));
		html = html + wrapTR(wrapTD("Flowers taken")+wrapTDMatchup(summary.flowers)+wrapTDMatchup(avgFlowers));
		html = html + wrapTR(wrapTD("Swagger gain")+wrapTDMatchup(summary.swagger)+wrapTDMatchup(avgSwagger));
	}

	html=html+"</tbody></table>";
	return html;
}
string formatResults() {
	string html = "<table style='margin-top: 10px;' border='1' cellspacing='1'><tbody>";
	string header = "<tr style='font-size: 12px;'>";
	header += "<th>Mini Name</th>";
	header += "<th colspan='1'>Normal Score</th>";
	header += "<th colspan='1'>Hardcore Score</th>";
	header += "<th colspan='1'>Total Games</th>";
	header += "<th colspan='1'>Offense</th>";
	header += "<th colspan='1'>Defense</th>";
	header += "</tr>";
	html += header;

	foreach key in TitleIndex {
		string thisTitle = TitleIndex[key];

		OneRound thisContest = summary.contests[thisTitle];
		int offenseFights = thisContest.offense;
		int defenseFights = thisContest.defense;
		int totalFights = offenseFights + defenseFights;

		{
			int oWins = thisContest.oWins;
			int dWins = thisContest.dWins;
			int tWins = oWins+dWins;

			int oLoss = offenseFights - oWins;
			int dLoss = defenseFights - dWins;
			int tLoss = oLoss + dLoss;

			string row;

			// title - total - score
			if (totalFights!=0){
				int tPerc = truncate(to_float(tWins)/totalFights*100);
				row += wrapTD(thisTitle);
				row += wrapTDMatchup(currentScore[key]);
				row += wrapTDMatchup(currentScoreHC[key]);
				row += wrapTDMatchup(offenseFights + defenseFights, 101);

			} else {
				row += wrapTD(thisTitle);
				row += wrapTDMatchup(0);
				row += wrapTDMatchup(0);
				row += wrapTDMatchup(0, 101);
			}

			// offense column
			if(offenseFights!=0){
				int oPerc = truncate(to_float(oWins)/offenseFights*100);
				row += createMatchupCell(oWins, oLoss, oPerc);

			} else {
				row += wrapTDMatchup('N/A', 101);
			}

			// defense column
			if(defenseFights!=0){
				int dPerc = truncate(to_float(dWins)/defenseFights*100);
				row += createMatchupCell(dWins, dLoss, dPerc);

			} else {
				row += wrapTDMatchup('N/A', 101);
			}

			// done
			html = html + wrapTR(row);
		}
	}

	html = html + "</tbody></table>";
	return html;
}
string renderMatchups(){
	string html = '<table border="1" cellspacing="1"><tbody>';
	int matchupNum = 0;

	// build header
	string headerHtml = '<tr style="font-size: 12px"><th>Opponent Name</th>';
	foreach key in TitleIndex {
		string minigameTitle = TitleIndex[key];
		if (minigameTitle == 'Whole Fights') {
			minigameTitle = 'Total Fights';
		}
		headerHtml = headerHtml + '<th style="width: 50px">' + minigameTitle + '</th>';
	}
	headerHtml += '<th style="width: 50px">Victory Chance</th>';
	html += headerHtml + '</tr>';

	// build rows
	foreach matchupName in processedMatchups {
		if (matchupNum > get_property("pvpBookkeeper.matchups").to_int()) {
			break;
		} else {
			matchupNum ++;
		}

		string rowHtml;
		Matchup matchupData = processedMatchups[matchupName];

		rowHtml += wrapTD(matchupData.opponentName);

		foreach key in TitleIndex {
			MinigameHistory miniHistory = matchupData.history[key];
			string minigameTitle = TitleIndex[key];
			boolean hasRecentVictory = matchupData.mostRecent[key] == 1;

			// render Total Fights column
			if (minigameTitle == 'Whole Fights' && matchupData.totalMatched != 0) {
				int matchupWinRatio = get_matchup_win_rate(matchupData);
				rowHtml += createMatchupCell(matchupData.winsMatched, matchupData.lossesMatched, matchupWinRatio, hasRecentVictory);

			// regular mini column
			} else if (miniHistory.total != 0) {
				int winRatio = truncate(to_float(miniHistory.wins)/miniHistory.total*100);
				rowHtml += createMatchupCell(miniHistory.wins, miniHistory.losses, winRatio, hasRecentVictory);

			// column with no results
			} else {
				rowHtml += wrapTDMatchup('N/A', 101);
			}
		}

		// generate estimated victory chance
		int minisWithDataCount = matchupData.mostRecent.count();
		int latestVictoryCount = 0;
		foreach idx, recentValue in matchupData.mostRecent {
			if (recentValue == 1) { // 1 means latest mini was won
				latestVictoryCount += 1;

			} else if (recentValue == 0) { // 0 means no data
				minisWithDataCount -= 1;
			}
		}

		int latestLossCount = minisWithDataCount - latestVictoryCount;
		int victoryChance = truncate((to_float(latestVictoryCount)/matchupData.mostRecent.count()) * 100);

		string changeHtml = '';
		changeHtml += '<font style="font-size: 13px;">' + victoryChance + '%' + '</font>';
		changeHtml += '<br/>';
		changeHtml += '<font style="font-size: 11px">' + latestVictoryCount + ' - ' + latestLossCount + '</font>';
		rowHtml += wrapTDMatchup(changeHtml, min(truncate(victoryChance * 1.5), 100));

		// done with row
		html = html + wrapTR(rowHtml);
	}

	//
	int remainingMatchups = processedMatchups.count() - matchupNum;

	html = html + "</tbody></table>";
	html += '<span style="font-size: 12px; margin-top: 5px;">...plus ' + remainingMatchups + ' other matchups.</span>';

	return html;
}
// --
void setCompact(){
	string currentSettings = visit_url("account.php?tab=interface");
	string compactedPattern = "<input[ a-zA-Z=\"0-9]*checked=\"checked\"[ a-zA-Z0-9=\"]*name=\"flag_compactfights\"[ a-zA-Z=\"0-9]*/>";
	matcher compactMatcher = create_matcher(compactedPattern,currentSettings);

	if(compactMatcher.find()){
		compact=true;
		print("Detected that settings are marked for compact mode");
		playersPattern="<a style\=\"font-weight: bold\" href\=\"showplayer.php\\?who\=\\d+\">(.*?)</a> vs <a style\=\"font-weight: bold\" href\=\"showplayer.php\\?who\=\\d+\">(.*?)</a>";
		contestPattern="<td nowrap><b>(.*?)</b></td><td><b>(.*?)</b>(.*?)</td>";
		fitePattern="<tr><td colspan=\"2\" align=\"center\"><b>(.*?)</b> Wins!</td>";
	}
	else{
		compact=false;
		print("Detected that settings are for extended mode");
		playersPattern="<a href=\"showplayer.php\\?who=\\d+\"><b>(.*?)</b></a> calls out <a href=\"showplayer.php\\?who=\\d+\"><b>(.*?)</b></a> for battle!";
		contestPattern= "<tr[a-zA-Z0-9/=\":. ]*?>\s*?<td[a-zA-Z0-9/=\":. ]*?>\s*?(<img[a-zA-Z0-9/=\":. _]*?>)?\s*?</td>.*?<center>\s*?Round \\d+: <b[a-zA-Z0-9/=\":. ]*?>(.*?)</b>\s*?<div[a-zA-Z0-9/=\":. ]*?>.*?</div>\s*?</center>\s*?<p>(.*?)</td>\s*?<td[a-zA-Z0-9/=\":. ]*?>\s*?(<img[a-zA-Z0-9/=\":. _]*?>)?\s*?</td>\s*?</tr>";
		fitePattern="<p><span style=\"font-size: 120%;\"><b>(.*?)</b> won the fight";
	}
}
string greeting(){
	string myGreet = '';
	if(get_property("pvpBookkeeper.greet")!="false"){
		myGreet +="<font size=+2>Welcome to</font><br/><font size=+3><b><a href=\"showplayer.php\?who=2205257\">Vhaeraun</a>'s Glorious PVP Bookkeeper!</b></font><br/>";
		myGreet += versionCheck();
		myGreet += '<a href=\"showplayer.php\?who=132084\">Dextrial</a> Edition</br><br>';
		myGreet +="If you provide a number, I'll show you statistics for that number of your most recent fights (this season).  If not, I'll use the default value, which can be changed at any time by setting the Mafia variable \"pvpBookkeeper.records\".  If this is your first time running the script, the default value will be set to 99,999.<br/><br/>";
		myGreet +="Color scheme can be modified by editing the data file pvpColors.txt in your KOLMafia data directory.<br/><br/>";
		myGreet +="KMail me any suggestions, and/or I love you gifts!<br/><br/>";
		myGreet +="This greeting can be permanently disabled by typing \"set pvpBookkeeper.greet=false\" into the CLI.  To get it back, set the same property to true (or anything else)<br/><br/>";
	}

	return myGreet;
}
string doMaths(int thisMax){
	print("Attempting to compile results for the last " + thisMax + " Fights...");

	if(get_property("pvpBookkeeper.matchups") == ""){
		set_property("pvpBookkeeper.matchups", 100);
	}

	if(thisMax==0){
		string property = get_property("pvpBookkeeper.records");
		if(property == ""){
			max=99999;
			set_property("pvpBookkeeper.records",max);
		}
		else{
			max = to_int(property);
		}
	}
	else{
		max = thisMax;
	}

	string archive = getArchive();
	string outputFileName = to_lower_case(myName)+ "_pvp_season_"+visitInformationBooth() +".dat";

	readPreviousResults(outputFileName);

	matcher logMatcher = create_matcher(viewPattern, archive);
	int i=0;
	while(logMatcher.find() && i<max){
		// print("found fightId: " + group(logMatcher,2));
		i=i+1;
		string oneFight=group(logMatcher,1);
		string fightId = group(logMatcher,2);
		string fightResults = group(logMatcher,3);

		summary.flowers = summary.flowers + flowersPicked(fightResults);
		summary.fame = summary.fame + fameTaken(fightResults);
		summary.swagger = summary.swagger + swaggerGained(fightResults);

		if(!(processedRecords contains fightId)){
			if(compact){
				ProcessedRecords[fightId] = evaluateFightCompact(oneFight, i);
			}
			else{
				ProcessedRecords[fightId] = evaluateFightFull(oneFight, i);
			}
		}

		evaluateProcessedFight(ProcessedRecords[fightId]);
		evaluateMatchup(ProcessedRecords[fightId]);
	}

	sort processedMatchups by get_sort_value(value);
	saveResults(outputFileName);

	return "Displaying " + get_property("pvpBookkeeper.matchups") + " matchups from the past " + i + " fights.";
}
void main(int thisMax){
	print_html(greeting());
	setCompact();
	print(doMaths(thisMax));

	// print_html(formatResults());
	// print_html(formatSummary());
	print_html(renderMatchups());
	// renderMatchups();
}
