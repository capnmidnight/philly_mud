var input = null;
var output = null;
var done = false;
var everyone = null;
var soFar = "";

function displayln(msg){
    soFar += msg + "\n\n";
    output.innerHTML = markdown.toHTML(soFar);
    output.scrollTop = output.scrollHeight;
}

function run() {
    try{
		document.getElementById("start").style.display = "none";
        done = false;
        everyone = {"player": new Body("test", 10),
                    "dave": new Body("test", 10),
                    "mark": new Body("test", 10),
                    "carl": new Body("test", 10)};
        setIds(everyone);
        for(var key in everyone) {
            if(key != "player")
                everyone[key].initAI();
        }
		var timer = null;
		var loop = function() {
			if(done){
				clearInterval(timer);
				document.getElementById("start").style.display = "inline-block";
			}
			else {
				for(var bodyId in everyone) {
                    var body = everyone[bodyId];
                    
                    if(bodyId == "player") {
                        body.printInformation();
                    }
                    else if(body.hp > 0) {
                        body.doAI();
                    }
                        
                    if(body.inputQ.length > 0) {
                        if(body.hp > 0) {
                            body.doCommand();
                        }
                        else { 
                            body.sysMsg("Knocked out!");
                            while(body.inputQ.length > 0) 
                                body.inputQ.shift();
                        }
                    }
                }
			}
		};
		timer = setInterval(loop, 100);
    }
    catch(exp){
        console.log(exp);
        clearInterval(timer);
    }
}

function submitCommand(evt){
    if(evt.keyCode == 13){
        var val = input.value.trim().toLowerCase();
        input.value = "";
        everyone["player"].inputQ.push(val);
        return false;
    }
    return true;
}

function setup(iId, oId){
    input = document.getElementById(iId);
    input.addEventListener("keypress", submitCommand, false);
    output = document.getElementById(oId);
}