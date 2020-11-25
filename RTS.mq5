
//+------------------------------------------------------------------+
//| The Reaction Trend System Expert Advisor                         |                                                  |
//| Author : Jose Augusto Fiorucci                                   |
//|   Department of Statistics, University of Brasilia               |
//|  FAPESP process: 2016/10431-7                                    | 
//| Colaborator 1: Geraldo Nunes Silva                               |
//|   Department of Applied Mathematics, Sao Paulo State University  |
//| Colaborator 2: Flavio Barboza                                    |
//|   Department of Administration, Federal University of Uberlandia |
//| 20/10/2020                                                       |   
//+------------------------------------------------------------------+


/*
Algoritmo:

Ponto Pivo:
X_bar <- (H+L+C)/3

Price Action points:
(1) B1 <- 2*X_bar - H         (Buy Point)
(2) S1 <- 2*X_bar - L         (Sell Point)
(3) HBOP <- 2*X_bar -2*L + H  (High Break Out Point)
(4) LBOP <- 2*X_bar -2*H + L  (Low Break Out Point)


Alguns detalhes:

a) os pontos de ação do dia atual são calculados com base no OHLC do dia anterior

b) a definição da letra do dia de hj é baseada na sequência "B","O","S","B","O","S",...
   
   Duas alternativas são apresentadas para inicializar a sequência:
   1) se a tendência geral é de alta (definido manualmente), então o dia (das ultimas duas ou três semanas) com o menor valor de mínimo é definido como "B".
      se a tendência geral é de baixa (definido manualmente), então o dia (das ultimas duas ou três semanas) com o maior valor de máximo é definido como "S".
   
   2) Phasing Technique: (Implementada no robô)
      Se o ultimo modo Trend do sistema foi de alta, então a sequência deve ser inicializada escolhendo o dia dentro desse modo com o maior máximo como sendo "S"
      Se o ultimo modo Trend do sistema foi de baixa, então a sequência deve ser inicializada escolhendo o dia dentro desse modo com o menor mínimo como sendo "B"     


Sistema:

1) Reaction mode:
   1.0) Cada dia recebe uma letra de acordo com a sequência "B","O","S","B","O","S",...
   1.1) Dia B,
      a) posições vendidas são atualizadas para TP=B1 e Stop=HBOP; 
      b) compra se Preço entre B1 e LBOP, com stop em LBOP e take profit em HBOP. 
      c) ao final do dia B, posições vendidadas são encerradas;
   1.2) Dia O, 
      a) posições compradas são atualizadas para TP=S1 e Stop=LBOP.
      b) nenhuma posição é aberta, mas qualquer posição que já estiver aberta é encerrado no fechamento;
   1.3) Dia S
      a) vende se Preço entre S1 e HBOP, com stop em HBOP e take profit em LBOP;

2) Trend mode: 
   --> Ativado quando o preço ultrapassa HBOP ou LBOP
   --> Desativado apenas quando o preço encosta em trailing stop (mínimo dos ultimos dois dias no caso de compra, maximo dos ultimos dois dias no caso de venda) 
   2.1) Compra se Preço em HBOP, com stop no mínimo dos ultimos dois dias;
   2.2) Vende se Preço em LBOP, com stop no máximo dos ultimos dois dias;
   3.3) Fecha a ordem apenas em trailing stop (máximo (se vendido) ou mínimo (se comprado) dos ultimos dois dias dependendo da posição);   
*/


#property copyright ""
#property link      "https://www.mql5.com"
#property version   "1.00"


//+------------------------------------------------------------------+
//| Include                                                          |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
CTrade trade_obj;

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input long MAGIC_NUMBER = 123;              // Magic Number

input double n_contracts = 1000;              // Number of contracts
input string horario_inicio = "10:05";        // Market open time: HH:MM      
input string horario_termino = "16:00";       // Market end time: HH:MM     
input string horario_fechamento = "16:55";    // Market close time: HH:MM  
input bool operar_reaction=true;              // Open orders in REACTION MODE? (Wilder: true)


input bool use_BOS=false;                    // Use "B","O","S"? (Wilder: both)
//input double spread = 5;                   // pts pro spread máximo
bool encerrar_fechamento_react = false;     // Close REACTION MODE orders at market close? (Wilder: false)
bool encerrar_fechamento_trend = false;     // Close TREND MODE orders at market close? (Wilder: false)

bool saidas_parciais = false;         // faz saídas parciais? // Nao implementado
double _pts_saida_1  = 1;           // pts para 1a parcial    // Nao implementado
double perc_saida_1  = 0.25;          // % mão - 1a parcial   // Nao implementado
double _pts_saida_2  = 2;           // pts para 2a parcial    // Nao implementado
double perc_saida_2  = 0.25;          // % mão - 2a parcial   // Nao implementado

 bool mov_stop_reaction = true;        // Update Stop on REACTION MODE? (Wilder: true)
 bool mov_stop_contrario = true;       // Update stop to worse?? (Wilder: true)
 bool mov_tp_reaction = true;          // Update TP on REACTION MODE? (Wilder: true)

bool mov_stop_trend = true;                 // Update Stop on TREND MODE? (Wilder: true)

 double min_amplitude = 0;            // Min Amplitude in pts (Wilder: 0)

 double max_salto = 1000;             // Max Jump in pts (Wilder: Inf)

 double stop_min = 0.0;               // Min Stop in pts  (Wilder: 0)

 double stop_max = 1000;               // Max Stop in pts (Wilder: Inf)

enum enumActionPoints
{
   Wilder = 0,
   GARCH = 1,
};

input enumActionPoints actionPoints=1;  // Action Points?  (Wilder: Wilder)

input double GARCH_UB_HBOP = 1.997;  // GARCH_UB_HBOP  (Wilder: NA)
input double GARCH_UB_S1 = 0.571;    // GARCH_UB_S1  (Wilder: NA)
input double GARCH_LB_B1 = -0.5610;   // GARCH_LB_B1  (Wilder: NA)
input double GARCH_LB_LBOP = -2.048; // GARCH_LB_LBOP  (Wilder: NA)

input double GARCH_Hig_omega=0.064;  // GARCH_Hig_omega  (Wilder: NA)
input double GARCH_Hig_alpha=0.040; // GARCH_Hig_alpha  (Wilder: NA)
input double GARCH_Hig_beta=0.926;   // GARCH_Hig_beta   (Wilder: NA)

input double GARCH_Low_omega=0.109;  // GARCH_Low_omega  (Wilder: NA)
input double GARCH_Low_alpha=0.058;  // GARCH_Low_alpha  (Wilder: NA)
input double GARCH_Low_beta=0.888;   // GARCH_Low_beta   (Wilder: NA)



//+------------------------------------------------------------------+
//| Variaveis globais                                                |
//+------------------------------------------------------------------+
long codigo_ticket = 0; // código da ordem aberta
double pts_saida_1,pts_saida_2,pts_saida_3;
double vol_min; // volume minimo de negociação
double point_size; // unidade minima do preço

int n_ordens_compra_dia=0; // contadores pro numero de ordens em um dia
int n_ordens_venda_dia=0;

enum enumMode
{
   Reaction = 0,
   Trend = 1,
};
enumMode modo_atual = 0; // modo de operação atual

string BOS = "O"; // no modo REACTION: B indica dia de venda, O indica dia sem operacao e S indica dia de venda

bool trend_alta = true; // 1 o ultimo modo TREND foi de alta, 0 se o ultimo modo TREND foi de baixa

datetime last_trend_start = iTime(Symbol(),PERIOD_D1,20);
datetime last_trend_end = iTime(Symbol(),PERIOD_D1,5);

datetime datatime_barra = iTime(Symbol(),PERIOD_D1,0);

double high_ht;
double low_ht;




//+------------------------------------------------------------------+
//| Initialization function of the expert                            |
//+------------------------------------------------------------------+
int OnInit()
 {
   modo_atual = 0; // inicializa no modo Reaction
  
   n_ordens_compra_dia=0; // contadores pro numero de ordens em um dia
   n_ordens_venda_dia=0;
   
   point_size = SymbolInfoDouble(Symbol(),SYMBOL_TRADE_TICK_SIZE);
   Print("SYMBOL_TRADE_TICK_SIZE: ", point_size);
   
   vol_min = SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   Print("SYMBOL_VOLUME_MIN: ", vol_min);
   
   Print("SYMBOL_POINT: ", SymbolInfoDouble(Symbol(), SYMBOL_POINT) );
   
   pts_saida_1 = point_size*_pts_saida_1;
   pts_saida_2 = point_size*_pts_saida_2;
 
   Print("_Digits: ", _Digits);
   
   last_trend_start = iTime(Symbol(),PERIOD_D1,20);
   last_trend_end = iTime(Symbol(),PERIOD_D1,5);
   trend_alta = true;
   if( iClose(Symbol(),PERIOD_D1,5) < iClose(Symbol(),PERIOD_D1,20) )
      trend_alta = false;
   
   BOS = BOS_function();
   if(!use_BOS)
      BOS = "NA";  
   Print("Dia de hoje: ", BOS);
   
   if( actionPoints == GARCH ){
      Print("Bars: ", Bars(Symbol(),PERIOD_D1));
      high_ht = GARCH_vol(GARCH_Hig_omega, GARCH_Hig_alpha, GARCH_Hig_beta, true);
      low_ht = GARCH_vol(GARCH_Low_omega, GARCH_Low_alpha, GARCH_Low_beta, false);
      Print("high_ht: ", high_ht, ", low_ht: ", low_ht);
   }
   
   datatime_barra = iTime(Symbol(),PERIOD_D1,1);
	EventSetTimer(3);
  
	return(INIT_SUCCEEDED);
 }
  
  
  
  
//+------------------------------------------------------------------+
//| Deinitialization function of the expert                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- destroy timer
	EventKillTimer();
}
  
 
 
  
void OnTick(){
   //OnTimer();
}  
  
  
  
  
  
//+------------------------------------------------------------------+
//| "Timer" event handler function                                   |
//+------------------------------------------------------------------+
void OnTimer()
{
   
   codigo_ticket = 0; // limpa memoria
   
   
   
   // -------------- Verificações relacionadas ao TEMPO -----------------------------///
   datetime curTime = TimeCurrent();
   MqlDateTime curTimeStruc; 
   TimeToStruct(curTime, curTimeStruc);
   string yyyymmdd = StringFormat("%d/%d/%d" , curTimeStruc.year,curTimeStruc.mon,curTimeStruc.day); 
   
   datetime inicio = StringToTime( StringFormat("%s %s", yyyymmdd, horario_inicio) );
   datetime termino = StringToTime( StringFormat("%s %s", yyyymmdd, horario_termino) );
   datetime fechamento = StringToTime( StringFormat("%s %s", yyyymmdd, horario_fechamento) );
   
   
   // verifica se o fechamento esta proximo:
   // fecha todas as ordens se faltar menos 11 min para o fechamento
   if( curTime > fechamento-660 && PositionsTotal() > 0 ){
      if(encerrar_fechamento_react && modo_atual==Reaction ){
         Print("Mercado proximo ao fechamento: ", fechamento);
         Print("Encerrando ordens do modo REACTION");
         CloseAllPositions("Reaction");
      }
      
      if(encerrar_fechamento_trend){
         //Print("Mercado proximo ao fechamento: ", fechamento);
         //Print("Encerrando ordens do modo TREND");
         CloseAllPositions("Trend");
      }
       
      //return;
   }   
	
	
	// verifica se esta fora da janela de negociação
	if( curTime < inicio || curTime > fechamento){   
	   //PrintFormat("Fora da janela de operação: inicio %s, termino %s, fechamento %s, hora atual %s", TimeToString(inicio), TimeToString(termino), TimeToString(fechamento), TimeToString(curTime) );   
	   n_ordens_compra_dia=0; // contadores pro numero de ordens em um dia
      n_ordens_venda_dia=0;
	   
	   return;
	}

	
	// verifica se existe ordem aberta, se existir pega o código dela (codigo_ticket)   
	if( PositionsTotal() > 0 )
	{
   	string symb="";
   	long magic=0;		
   	
   	for(int i=PositionsTotal()-1; i>=0 ; --i){	   
   	   symb = PositionGetSymbol(i);
   	   magic = PositionGetInteger(POSITION_MAGIC);    	   
   	   if( symb == Symbol() && magic == MAGIC_NUMBER ){
   	      codigo_ticket = PositionGetInteger(POSITION_TICKET);
   	      //Print("codigo_ticket: ",codigo_ticket);
   	   }
   	}   
   }
   // ----------------------------------------------------------------------///
   
   
   
   
   
   
   // -------------- PREÇOS -------------------------------------------------///
	// OHLC do dia anterior
	//double open_ontem = iOpen(Symbol(),PERIOD_D1,1);
   double high_ontem  = iHigh(Symbol(),PERIOD_D1,1);
   double low_ontem   = iLow(Symbol(),PERIOD_D1,1);
   double close_ontem = iClose(Symbol(),PERIOD_D1,1);
   
   // OHLC dois dias atras
	//double open_anteontem = iOpen(Symbol(),PERIOD_D1,2);
   double high_anteontem  = iHigh(Symbol(),PERIOD_D1,2);
   double low_anteontem   = iLow(Symbol(),PERIOD_D1,2);
   //double close_anteontem = iOpen(Symbol(),PERIOD_D1,2);
   
   double min_low = MathMin( low_anteontem, low_ontem );
   double max_high = MathMax( high_anteontem, high_ontem );
   
   // Ponto pivo
   double pivo = ( high_ontem + low_ontem + close_ontem ) / 3;
   
   // ask, bid, open, last - atuais
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
	double last = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
	double open = iOpen(Symbol(),PERIOD_D1,0);
	if( last < bid - 5*point_size || last > ask + 5*point_size ) // correção colocada após ser observado last=0 no backtest
	   last = NormalizeDouble((bid+ask)/2, _Digits);
	
	// action points  
	double HBOP = NormalizeDouble( 2*pivo - 2*low_ontem + high_ontem, _Digits); // High break out point
   double B1 = NormalizeDouble( 2*pivo - high_ontem, _Digits);                 // Buy point
	double S1 = NormalizeDouble( 2*pivo - low_ontem, _Digits);                  // Sell point
	double LBOP = NormalizeDouble( 2*pivo - 2*high_ontem + low_ontem, _Digits); // Low break out point
	
	if(actionPoints == GARCH){
	   
	   if( datatime_barra != iTime(Symbol(),PERIOD_D1,0) ){   // executa apenas uma vez por dia na abertura do mercado, "datatime_barra" é atualizado logo abaixo.
	      high_ht = GARCH_vol(GARCH_Hig_omega, GARCH_Hig_alpha, GARCH_Hig_beta, true);
         low_ht = GARCH_vol(GARCH_Low_omega, GARCH_Low_alpha, GARCH_Low_beta, false);
         Print("high_ht: ", high_ht, ", low_ht: ", low_ht);
	   }
	   
	   HBOP = MathExp( GARCH_UB_HBOP*MathSqrt(high_ht)/100 )*high_ontem;
	   S1 = MathExp( GARCH_UB_S1*MathSqrt(high_ht)/100 )*high_ontem;
	   B1 = MathExp( GARCH_LB_B1*MathSqrt(low_ht)/100 )*low_ontem;
	   LBOP = MathExp( GARCH_LB_LBOP*MathSqrt(low_ht)/100 )*low_ontem;
	   
	}
	
	
	double salto = open - close_ontem;         // dia de salto?
	
	// controle dos modos de operação (não muda no caso de existir ordem aberta)
	if(codigo_ticket == 0){
   	if( last < HBOP && last > LBOP ){
   	   if( modo_atual == Trend ){
   	      last_trend_end = iTime(Symbol(),PERIOD_D1,0);
   	      modo_atual = Reaction;
   	      BOS = BOS_function();
            Print("Dia de hoje: ", BOS);
          }  
   	}else{
   	   if(modo_atual != Trend){
      	   last_trend_start = iTime(Symbol(),PERIOD_D1,0);
      	   modo_atual = Trend;
      	   if(last < LBOP)
      	      trend_alta = false;
      	   else
      	      trend_alta = true;
   	   }      
   	}
	}
	
   // Inclui as setas no gráfico e calcula o BOS ( executa apenas uma vez por dia na abertura do mercado )
   if( datatime_barra != iTime(Symbol(),PERIOD_D1,0) ){
      objCreate(HBOP, true, modo_atual == Reaction );
      objCreate(S1, false, modo_atual == Reaction );
      objCreate(B1, true, modo_atual == Reaction );
      objCreate(LBOP, false, modo_atual == Reaction);
      datatime_barra = iTime(Symbol(),PERIOD_D1,0);
      
      BOS = BOS_function();
      Print("Dia de hoje: ", BOS);
      
      Print("Amplitude: ",  high_ontem-low_ontem);
      Print("Salto: ", salto);
      Print("Modo atual: ", EnumToString(modo_atual));
   }
	   
	// ----------------------------------------------------------------------///
	
	
	
	
	
	
	
	
	
	
	//------- código destinado ao gerenciamento de posição aberta -----------///
	if( PositionSelectByTicket(codigo_ticket) ){
	
	   //Print("entrei no gerenciamento");
	  
	   bool compra = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY; // 1 se é do tipo compra, 0 se é do tipo venda
	   double preco_abertura = PositionGetDouble(POSITION_PRICE_OPEN);
	   double SL = PositionGetDouble(POSITION_SL);
	   double TP = PositionGetDouble(POSITION_TP);
	   double vol = PositionGetDouble(POSITION_VOLUME);
	   string modo = PositionGetString(POSITION_COMMENT);
	   
	   double novo_SL=SL;
	   double novo_TP=TP;
	   
	   if(modo == "Reaction"){
	      
	      if( mov_stop_reaction ){
   	      if( compra && MathAbs(SL-LBOP) > 2*point_size  && (BOS=="O"||BOS=="S"||BOS=="NA") ){
   	         novo_SL = LBOP;
   	      }
   	         
   	      if( !compra && MathAbs(SL-HBOP) > 2*point_size && (BOS=="O"||BOS=="B"||BOS=="NA") ){
   	         novo_SL = HBOP;
   	      }
	      }
	      
	      if( mov_tp_reaction ){
   	      if( compra && MathAbs(TP-S1) > 2*point_size  && (BOS=="O"||BOS=="S"||BOS=="NA") ){
   	         novo_TP = S1;
   	      }
   	         
   	      if( !compra &&  MathAbs(TP-B1) > 2*point_size && (BOS=="O"||BOS=="B"||BOS=="NA") ){
   	         novo_TP = B1;
   	      }
	      }
	      
	      // Encerra as posições do modo Reaction no fechamento, de acordo com os dias.
	      if( curTime > fechamento-660 && ( BOS=="O" || ((compra && BOS=="S")||( !compra && BOS=="B"))) ){
	         CloseAllPositions("Reaction");
	      }   
	                      
	   }
	   
	   
	   
	   if(modo == "Trend" && mov_stop_trend){
	      
	      if( compra && MathAbs(SL-min_low) > 2*point_size )
	         novo_SL = min_low;
	         
	      if( !compra && MathAbs(SL-max_high) > 2*point_size )
	         novo_SL = max_high;
	            	   
	   }
	   
	    
      if( modo == "Reaction" && ( (compra && (novo_SL > bid || novo_TP < bid) ) || (!compra && ( novo_SL < ask || novo_TP > ask ) ) ) ){
         CloseAllPositions( modo );
         return;
      }
      
      if( modo == "Trend" &&  ( (compra && novo_SL > bid  ) || (!compra && novo_SL < ask  ) ) ){
         CloseAllPositions( modo );
         return;
      }
	      
	    
      /*if(MathAbs(preco_abertura - novo_SL)<stop_min){
	      if(compra){
	         novo_SL = preco_abertura-stop_min;
	      }else{
	         novo_SL = preco_abertura+stop_min;
	      }
	   }*/
   	   
	   if( (compra && (preco_abertura - novo_SL)>stop_max) || (!compra && (-preco_abertura + novo_SL)>stop_max) ){
	      if(compra){
	         novo_SL = preco_abertura-stop_max;
	      }else{
	         novo_SL = preco_abertura+stop_max;
	      }
	   }
	   
   	novo_SL = NormalizeDouble(novo_SL,_Digits);
	   novo_TP = NormalizeDouble(novo_TP,_Digits);
	   
	   if(!mov_stop_contrario && ( (compra && novo_SL < SL) || (!compra && novo_SL > SL) ) ){
	      novo_SL = SL;
	   }
	      
	   if( novo_SL != SL || novo_TP != TP ){     
	      if( trade_obj.PositionModify(codigo_ticket, novo_SL, novo_TP) ){
	         Print("SL atualizado para ", novo_SL, ", TP atualizado para ", novo_TP);
	      }else{
	         Print("Erro ao tentar atualizar SL: ", GetLastError());
	      }
	      
	   }
	   
	   
	   
	   // saidas parciais
	   if(saidas_parciais){
	   
   	   double preco_saida_1 = preco_abertura + compra*pts_saida_1 - (1-compra)*pts_saida_1;
   	   double preco_saida_2 = preco_abertura + compra*pts_saida_2 - (1-compra)*pts_saida_2;
   	   double preco_saida_3 = preco_abertura + compra*pts_saida_3 - (1-compra)*pts_saida_3;
   	   
   	   int saida = 0;
   	   double preco_saida=0;
   	   double novo_vol=vol;
   	   
         if( vol > n_contracts*(1-perc_saida_1) && ( ( compra==true && last > preco_saida_1 ) || ( compra==false && last < preco_saida_1 ) ) ){
            saida = 1;
            preco_saida = preco_saida_1;  
            novo_vol = novo_vol*(1-perc_saida_1);
         }
            
         if( vol > n_contracts*(1-perc_saida_2) && ( ( compra==true && last > preco_saida_2 ) || ( compra==false && last < preco_saida_2 ) ) ){
            saida = 2;
            preco_saida = preco_saida_2;
            novo_vol = novo_vol*(1-perc_saida_2);
         }
         
   	   
   	   // saidas parciais
   	   bool erro_saida_parcial = true;
   	   if(saidas_parciais && saida > 0){
   	      
   	      double vol_close = vol_min*NormalizeDouble( (vol - novo_vol)/vol_min, 0 );
   	      
   	      Print("Tentando saida parcial ", saida ," de ", vol_close, " no valor ", preco_saida, ". Last: ", last, ", Bid: ", bid, ", Ask: ", ask);
   	      
   	      if( trade_obj.PositionClosePartial(_Symbol,vol_close,10) ){
   	        erro_saida_parcial = false; 
   	      }else{
   	        Print("Erro ao tentar saida parcial: ", GetLastError());
   	        
   	        string ordem_contraria ="";
   	        if(compra){
   	         ordem_contraria = "SELL";
   	        }else{
   	         ordem_contraria = "BUY";
   	        }
   	         
   	        if( envia_ordem( ordem_contraria, vol_close )){
   	         erro_saida_parcial = false;
   	        }else{
   	         Print("Erro 2 ao tentar saida parcial: ", GetLastError());
   	         erro_saida_parcial = true;
   	        }
   	           
   	      }      
   	   }
   	   
	   }// fim do saidas parciais
	   
	   return;
	} 	
	// --------------------------------------------------------------------------/// 
	
	
	

	
	
	
	// --------- código destinado a abrir uma nova ordem   -----------------///
	// será executado apenas se ainda não existe ordem aberta
	if(codigo_ticket == 0 && curTime > inicio && (curTime < termino || modo_atual == Trend) && high_ontem-low_ontem > min_amplitude && max_salto > MathAbs(salto)){
   	
   	string order = "NULL";
   	ENUM_ORDER_TYPE order_type=0;
      double order_price=0;
      double stop=0;
      double tp=0;
   	
   	
   	// controle de abertura de ordens no modo Reaction
   	if( modo_atual == Reaction && operar_reaction ){
   	   
   	   if( ask < B1 && (BOS=="B"||BOS=="NA") && n_ordens_compra_dia < 2 ){ // setup para compra
   	      order = "BUY";
   	      order_type = ORDER_TYPE_BUY;
      		order_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      		stop = LBOP;
      		tp = HBOP;
      	}
      	
      	if( ask > S1 && (BOS=="S"||BOS=="NA") && n_ordens_venda_dia < 2 ){ // setup para venda
      	   order = "SELL";
      	   order_type = ORDER_TYPE_SELL;
      		order_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      		stop = HBOP;
      		tp = LBOP;
      	}
      	   
   	}
   	
   	
   	// controle de abertura de ordens no modo Trend
   	if( modo_atual == Trend ){
   	   
   	   if( ask > HBOP ){ // setup para compra
   	      order = "BUY";
   	      order_type = ORDER_TYPE_BUY;
      		order_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      		stop = min_low;
      		tp = 0; // Não define tp
      	}
      	
      	if( bid < LBOP ){ // setup para venda
      	   order = "SELL";
      	   order_type = ORDER_TYPE_SELL;
      		order_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      		stop = max_high;
      		tp = 0; // Não define tp
      	}
      	   
   	}
   	
   	  	
   	
   	// envio da ordem 
   	if(order != "NULL" ){
   	
   	   if(MathAbs(order_price - stop)<stop_min){
   	      if(order_type == ORDER_TYPE_BUY){
   	         stop = order_price-stop_min;
   	      }else{
   	         stop = order_price+stop_min;
   	      }
   	   }
   	   
   	   if(MathAbs(order_price - stop)>stop_max){
   	      if(order_type == ORDER_TYPE_BUY){
   	         stop = order_price-stop_max;
   	      }else{
   	         stop = order_price+stop_max;
   	      }
   	   }
      	
      	Print("Opening position");
      	MqlTradeRequest request = {0};
      	MqlTradeResult result = {0};
      	ZeroMemory(request);
      	ZeroMemory(result);
      	request.action = TRADE_ACTION_DEAL;
      	request.magic = MAGIC_NUMBER;
      	request.symbol = Symbol();
      	request.volume = n_contracts;
      	request.type_time = ORDER_TIME_DAY;
      	//request.expiration = TimeCurrent() + 3600; // 5 hours to expirate
      	request.price = NormalizeDouble(order_price, _Digits);
      	request.sl = NormalizeDouble(stop, _Digits);
      	request.tp = NormalizeDouble(tp, _Digits);
      	request.type = order_type;
      	request.comment = EnumToString( modo_atual ); // será utilizado no gerenciamento da ordem;
      	
      	if(OrderSend(request, result)){
      	   if( order_type == ORDER_TYPE_BUY ){
      	      n_ordens_compra_dia =  n_ordens_compra_dia + 1;
      	   }else{
      	      n_ordens_venda_dia =  n_ordens_venda_dia + 1;
      	   }
      	}else{
      	 	Print("Couldn't place order: ", GetLastError());
      	}
      	
      	return; 	
   	} 	
   	
   }
	// ----------------------------------------------------------------------///
		
	
  }
//+-------------------------------------------------------------------------------+




bool CloseAllPositions(string comment)
{
	ulong ticket;
	bool closedAny = 0;
	//--- loop throught all positions
	for(int i=PositionsTotal()-1; i>=0 ; --i)
	{
		if((ticket=PositionGetTicket(i))>0)
		{
			bool test = PositionSelectByTicket(ticket);
			
			if( MAGIC_NUMBER == PositionGetInteger(POSITION_MAGIC) &&
				 Symbol() == PositionGetString(POSITION_SYMBOL) &&
				 comment == PositionGetString(POSITION_COMMENT) &&
				 test )
			{
				trade_obj.PositionClose(ticket);
				closedAny = 1;
   		}
   	}	
	}
	return closedAny;
}


// order = "BUY" ou "SELL"
bool envia_ordem( string order, double vol ){
   ENUM_ORDER_TYPE order_type;
 	     
	double order_price, stop, tp;
	ENUM_TRADE_REQUEST_ACTIONS action;
	
	if(order == "BUY") {
		order_type = ORDER_TYPE_BUY;
		order_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
		stop = 0;//order_price - StopLoss;
		tp = 0;//order_price + Alvo;
		action = TRADE_ACTION_DEAL;
	} else if(order == "SELL") {
		order_type = ORDER_TYPE_SELL;
		order_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
		stop = 0;//order_price + StopLoss;
		tp = 0;//order_price - Alvo;
		action = TRADE_ACTION_DEAL;
	} else {
		Print("No orders to open");
		return false;
	}

	MqlTradeRequest request = {0};
	MqlTradeResult result = {0};
	ZeroMemory(request);
	ZeroMemory(result);
	request.action = action;
	request.magic = MAGIC_NUMBER;
	request.symbol = Symbol();
	request.volume = vol;
	request.type_time = ORDER_TIME_DAY;
	//request.expiration = TimeCurrent() + 3600; // 5 hours to expirate
	request.price = NormalizeDouble(order_price, _Digits);
	request.sl = NormalizeDouble(stop, _Digits);
	request.tp = NormalizeDouble(tp, _Digits);
	request.type = order_type;
	
	if(OrderSend(request, result)){
	 	return true;
   }
   
   return false;
}




int objCode = 0;

void objCreate(double valor, bool buy, bool reaction){
   string nomeObj = "l"+ IntegerToString(objCode,0,0);
   //Print("colocando seta no valor: ", valor);
   
   if(buy)
      ObjectCreate(0,nomeObj,OBJ_ARROW_BUY,0,iTime(Symbol(),PERIOD_D1,0),valor);
   else
      ObjectCreate(0,nomeObj,OBJ_ARROW_SELL,0,iTime(Symbol(),PERIOD_D1,0),valor);
            
   if( reaction ) 
      ObjectSetInteger(0,nomeObj,OBJPROP_COLOR,clrWhiteSmoke);
   else
      ObjectSetInteger(0,nomeObj,OBJPROP_COLOR,clrPaleVioletRed);
      
   //ObjectSetInteger(0,nomeObj,OBJPROP_ARROWCODE,2); //4
   //ObjectSetInteger(0,nomeObj,OBJPROP_WIDTH,4);
   
   objCode++;
}


// função que retorna se o dia de hoje é B, O ou S
string BOS_function(){
   if( modo_atual == Trend || !use_BOS )
      return "NA";
      
   int n_start = Bars(Symbol(),PERIOD_D1,last_trend_start,iTime(Symbol(),PERIOD_D1,0))-1;
   int n_end = Bars(Symbol(),PERIOD_D1,last_trend_end,iTime(Symbol(),PERIOD_D1,0))-1; 
   
   Print("last_trend_start: ", last_trend_start, ", n_start: ", n_start);  
   Print("last_trend_end: ", last_trend_end, ", n_end: ", n_end); 
   
   if(!trend_alta){ // se o ultimo TREND foi de baixa --> inicia o menor valor do período com B
      
      int idx_min; //= iLowest(Symbol(),PERIOD_D1,MODE_LOW,n_start-n_end,n_end);    
      idx_min = n_start;
      for(int i = n_start; i>=n_end; i--){
         if( iLow(Symbol(),PERIOD_D1,i) < iLow(Symbol(),PERIOD_D1,idx_min) )
            idx_min  = i;
      }
      
      Print("Last Trend: BAIXA, idx_min = ", idx_min, ", dia_min: ", iTime(Symbol(),PERIOD_D1,idx_min));
      
      double resto =  MathMod(idx_min, 3);
      
      if( MathAbs(resto - 0) < 0.01 )
         return "B"; 
      
      if( MathAbs(resto - 1) < 0.01 )
         return "O";
         
      if( MathAbs(resto - 2) < 0.01 )
         return "S";
   
   }else{ // e o ultimo TREND foi de alta --> inicia o maior valor do período com S
      
      int idx_max;// = iHighest(Symbol(),PERIOD_D1,MODE_HIGH,n_start-n_end,n_end);
      idx_max = n_start;
      for(int i = n_start; i>=n_end; i--){
         if( iHigh(Symbol(),PERIOD_D1,i) > iHigh(Symbol(),PERIOD_D1,idx_max) )
            idx_max  = i;
      }
      
      Print("Last Trend: ALTA, idx_max = ", idx_max, ", dia_max: ", iTime(Symbol(),PERIOD_D1,idx_max));
      
      double resto =  MathMod(idx_max, 3);
      
      if( MathAbs(resto - 0) < 0.01 )
         return "S"; 
      
      if( MathAbs(resto - 1) < 0.01 )
         return "B";
         
      if( MathAbs(resto - 2) < 0.01 )
         return "O";
   
   }
       
   return "NA";       
}


 


double GARCH_vol(double omega, double alpha, double beta, bool High){
   
   double rt;
   double ht=omega;
   
   int n=Bars(Symbol(),PERIOD_D1); 
   if( n > 500){
      n = 500;
   }
   
   Print("n =  ", n);

   if(High){
      for(int i=n-5; i>=1; --i){
         rt = 100*( MathLog(iHigh(Symbol(),PERIOD_D1,i)) - MathLog(iHigh(Symbol(),PERIOD_D1,i+1)) );
         ht = omega + alpha*rt*rt + beta*ht;
      }
   }else{
      for(int i=n-5; i>=1; --i){
         rt =  100*( MathLog(iLow(Symbol(),PERIOD_D1,i)) - MathLog(iLow(Symbol(),PERIOD_D1,i+1)) );
         ht = omega + alpha*rt*rt + beta*ht;
      }
   }
   
   return(ht);
}
