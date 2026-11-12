/// Example lines from the Lichess API specification (github.com/lichess-org/api), as single-line NDJSON.
enum LichessFixtures {
    static let gameStart = #"{"type":"gameStart","game":{"fullId":"p8Jy2ayw91cB","gameId":"p8Jy2ayw","fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","color":"white","lastMove":"","source":"friend","status":{"id":20,"name":"started"},"variant":{"key":"standard","name":"Standard"},"speed":"blitz","perf":"blitz","rated":true,"hasMoved":false,"opponent":{"id":"aaron","username":"Aaron","rating":879},"isMyTurn":true,"secondsLeft":300,"rating":784,"compat":{"bot":false,"board":true},"id":"p8Jy2ayw"}}"#

    static let gameFinish = #"{"type":"gameFinish","game":{"fullId":"p8Jy2ayw91cB","gameId":"p8Jy2ayw","fen":"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2","color":"white","lastMove":"e7e5","source":"friend","status":{"id":31,"name":"resign"},"variant":{"key":"standard","name":"Standard"},"speed":"blitz","perf":"blitz","rated":true,"hasMoved":true,"opponent":{"id":"aaron","username":"Aaron","rating":879,"ratingDiff":25},"isMyTurn":false,"secondsLeft":300,"winner":"black","rating":784,"ratingDiff":-19,"compat":{"bot":false,"board":true},"id":"p8Jy2ayw"}}"#

    static let gameStartAI = #"{"type":"gameStart","game":{"fullId":"abcdefgh1234","gameId":"abcdefgh","fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","color":"black","lastMove":"","source":"ai","status":{"id":20,"name":"started"},"variant":{"key":"standard","name":"Standard"},"speed":"correspondence","perf":"correspondence","rated":false,"hasMoved":false,"opponent":{"id":null,"username":"Stockfish level 1","ai":1},"isMyTurn":false,"compat":{"bot":false,"board":true},"id":"abcdefgh"}}"#

    static let challenge = #"{"type":"challenge","challenge":{"id":"qUfdwN17","url":"https://lichess.org/game/qUfdwN17","status":"created","challenger":{"name":"Adriana","flair":"smileys.smiling-cat-with-heart-eyes","id":"adriana","rating":627,"provisional":true},"destUser":{"name":"Gabriela","id":"gabriela","rating":1603,"online":true},"variant":{"key":"standard","name":"Standard","short":"Std"},"rated":false,"speed":"correspondence","timeControl":{"type":"unlimited"},"color":"random","finalColor":"black","perf":{"icon":"","name":"Correspondence"}},"compat":{"bot":false,"board":true}}"#

    static let challengeCanceled = #"{"type":"challengeCanceled","challenge":{"id":"pWdpCP3w","url":"https://lichess.org/game/pWdpCP3w","status":"canceled","challenger":{"name":"Elena","title":"IM","id":"elena","rating":2252},"destUser":{"name":"Diego","id":"diego","rating":1915,"online":true},"variant":{"key":"standard","name":"Standard","short":"Std"},"rated":false,"speed":"correspondence","timeControl":{"type":"unlimited"},"color":"random","finalColor":"white","perf":{"icon":"","name":"Correspondence"}}}"#

    static let challengeDeclined = #"{"type":"challengeDeclined","challenge":{"id":"qUfdwN17","url":"https://lichess.org/game/qUfdwN17","status":"declined","challenger":{"name":"Adriana","id":"adriana","rating":627,"provisional":true},"destUser":{"name":"Gabriela","id":"gabriela","rating":1603,"online":true},"variant":{"key":"standard","name":"Standard","short":"Std"},"rated":false,"speed":"correspondence","timeControl":{"type":"unlimited"},"color":"random","finalColor":"black","perf":{"icon":"","name":"Correspondence"},"declineReason":"I'm not accepting challenges at the moment.","declineReasonKey":"generic"}}"#

    static let gameFull = #"{"id":"qP8XaFtN","variant":{"key":"standard","name":"Standard","short":"Std"},"speed":"blitz","perf":{"name":"Blitz"},"rated":false,"createdAt":1793058022546,"white":{"id":"kenneth","name":"Kenneth","title":null,"rating":566},"black":{"id":"salma","name":"Salma","title":null,"rating":662},"initialFen":"startpos","clock":{"initial":300000,"increment":0},"type":"gameFull","state":{"type":"gameState","moves":"","wtime":300000,"btime":300000,"winc":0,"binc":0,"status":"started"}}"#

    static let gameState = #"{"type":"gameState","moves":"e2e4","wtime":300000,"btime":300000,"winc":0,"binc":0,"status":"started"}"#

    static let opponentGone = #"{"type":"opponentGone","gone":true,"claimWinInSeconds":51}"#

    static func state(moves: String, status: String = "started", extra: String = "") -> String {
        #"{"type":"gameState","moves":"\#(moves)","wtime":0,"btime":0,"winc":0,"binc":0,"status":"\#(status)"\#(extra)}"#
    }

    static let playing = #"{"nowPlaying":[{"fullId":"p8Jy2ayw91cB","gameId":"p8Jy2ayw","fen":"rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2","color":"white","lastMove":"e7e5","source":"friend","status":{"id":20,"name":"started"},"variant":{"key":"standard","name":"Standard"},"speed":"correspondence","perf":"correspondence","rated":false,"hasMoved":true,"opponent":{"id":"aaron","username":"Aaron","rating":879},"isMyTurn":true,"secondsLeft":250000}],"nbMyTurn":1}"#
}
