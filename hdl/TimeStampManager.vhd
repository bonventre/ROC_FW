																																											--------------------------------------------------------------------------------
-- Company: Fermilab
-- Notes: Time-Stamp manages synchronization betweeen ROCs and eventmarker.   

-- Targeted device: <Family::PolarFire> <Die::MPF300T> 
-- Author: Jose Berlioz
--
--------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.all;            
use IEEE.NUMERIC_STD.all; 
use IEEE.STD_LOGIC_MISC.all; 
								   						   
library work;
use work.algorithm_constants.all; 

entity timeStamp_Manager is  	       
	port(			
			RESET_N							:   in		std_logic;	  
			ENABLE_LOOPBACK_DELAY			:   in      std_logic;
			LOOPBACKMODE_40 				: 	in 		std_logic;	
			EVENTMARKER_40  				: 	in		std_logic;
			TCLK							:	in      std_logic;   
			EVENT_START_DELAY_FINE_TCLK		:   in      std_logic_vector(15 downto 0);	   
			ALIGNMENT_REQ					:   in		std_logic; 
			HEARTBEAT_EVENT_WINDOW_TAG		:   in      STD_LOGIC_VECTOR(EVENT_WINDOW_TAG_SIZE-1 downto 0);
			
			EVENT_WINDOW_TAG				:   out     STD_LOGIC_VECTOR(EVENT_WINDOW_TAG_SIZE-1 downto 0);
			TIMESTAMP   					:	out     std_logic_vector (31 downto 0);	  
			LOOPBACKMARKER_OUT				:	out		std_logic;
			TIMESTAMP_RESET					:   out		std_logic;

 --         --Error Detection Flags								
 			TIMESTAMP_OF					:   out		std_logic;
            TCLK_ALIGNED                    :   out     std_logic;
			EVENTEARLYERROR     			:   out		std_logic 
			
			
	    );
end timeStamp_Manager;
                                                                                                   

architecture arch of timeStamp_Manager is     						
	constant flagDetectionEdge			: integer  := 2; --1;  -- NUM_OF_TCLK_IN_40 cycle. 0 to NUM_OF_TCLK_IN_40-1. Flags happen on 2nd tick or index 1. CANT BE 0	
	constant edgeMinusOne				: integer  := flagDetectionEdge - 1;																							
	constant OFFSET_COUNTER_SIZE		: natural  := 32;
	constant offset_counter_saturated	: unsigned (OFFSET_COUNTER_SIZE-1 downto 0) := (others => '1');
	
	constant eventStartDelayCoarse40	: integer  := 0;
	constant loopbackDelay     			: integer  := eventStartDelayCoarse40*2; 
	                                	
	signal eventDetected    			:   std_logic;	 
	signal startLoopbackDelay			: 	std_logic;
                                    	
	signal loopbackLatch 				: 	std_logic;
	signal eventLatch    				:   std_logic;	
	signal eventLatch2					:   std_logic;  
	signal eventLatch3					:   std_logic;
	signal eventOut						:   std_logic;
	                                	
	signal startReset   				: 	std_logic;	 
	
	signal needAlignment			    : 	std_logic;
	signal needAlignment_2				:   std_logic;
	signal needAlignmentLatch			: 	std_logic;
	
	signal resetTimestampStrobe			:   std_logic;		  

	signal stepTCLKin40_incomingMarker	: 	unsigned	(2  downto 0); --counter for detection of Marker	  
	signal stepTCLKin40_ReturnMarker	:   unsigned    (2 downto 0);
	signal timeCounter					:  	unsigned	(31 downto 0); --timeStamp register
	signal timestampDelayCounter40		:   unsigned    (3  downto 0);
	signal fineDelayCounterTCLK			:  	unsigned	(15 downto 0); --delay that offers on-demand event marker shifts.	
	signal loopbackDelayCounter			:   unsigned	(15 downto 0); --delay for loopback fine delay mode.
	signal startFineDelay				:   std_logic;
	signal counterOverflow      		:   std_logic;	  
	signal returnMarker					:   std_logic;	
	signal returnLatch					:   std_logic;
	signal loopbackMarkerOut			:	std_logic;
	signal markerDone					:   std_logic;	  
	--signal alignmentResetStrobe		:   std_logic; 	 	
	signal eventEarlyError_Flag			:   std_logic;		
	signal resetLatch					:	std_logic;
	signal resetLatch2					:	std_logic;	
	signal alignment_req_latch			: 	std_logic;
	signal alignment_req_latch2			: 	std_logic;	  
	signal alignment_req_rising_edge	: 	std_logic;
	signal event_start_fine_delay_latch :   std_logic_vector(15 downto 0);	 
	signal wait_event_fine_delay		:   std_logic;	 
	signal domainState2					:   std_logic_vector(1 downto 0);
	signal loopback_delay_en_latch		:   std_logic;
	
	signal E_markerOffsetPlusOne 				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);	
	signal E_markerOffsetPlusTwo				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);
	signal E_markerOffsetMinusOne				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);
	signal E_markerOffsetMinusTwo				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);  	
	signal E_markerOffsetCenter					: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);  
	
--	signal L_markerOffsetPlusOne 				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);	
--	signal L_markerOffsetPlusTwo				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);
--	signal L_markerOffsetMinusOne				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);
--	signal L_markerOffsetMinusTwo				: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);  	
--	signal L_markerOffsetCenter					: unsigned (OFFSET_COUNTER_SIZE-1 downto 0);  
	
begin		   				 		 
	LOOPBACKMARKER_OUT 	<= loopbackMarkerOut;		
	TIMESTAMP 			<= std_logic_vector(timeCounter);	  
    TCLK_ALIGNED        <= not needAlignment;   
	TIMESTAMP_RESET 	<= 	resetTimestampStrobe;		
	
							
	--=======================
	--(1) Domain Transfer (40Mhz to 200Mhz). 					   
	--Input: EVENTMARKER, markerDone
    --RESET: RESET
	--Output: EventDetected -> (2), eventEarlyError -> OUT
	--=======================		  
	domainTransfer: process( TCLK )
	begin 
		if (rising_edge(TCLK)) then  		
			
			--(1A) SETUP LATCHES.	  
			alignment_req_latch					<= ALIGNMENT_REQ;
			alignment_req_latch2				<= alignment_req_latch;
			alignment_req_rising_edge			<= alignment_req_latch	and not alignment_req_latch2;											   
			
			eventLatch 		        			<= EVENTMARKER_40;   				--Latches help  a) Shift from different clock domains
			loopbackLatch 	        			<= LOOPBACKMODE_40;					--              b) Read edges of a signal
			needAlignmentLatch 					<= needAlignment;	 
			
			eventLatch2         				<= eventLatch;		
			eventLatch3							<= eventLatch2;			
			
			loopback_delay_en_latch				<= ENABLE_LOOPBACK_DELAY;
			
            --(1B) 40Mhz Counter @ TCLK. 												    
			stepTCLKin40_incomingMarker 	<= stepTCLKin40_incomingMarker + 1;	            --Wrapping counter in TCLK resetting every 40Mhz cycles.
			if(stepTCLKin40_incomingMarker = NUM_OF_TCLK_IN_40-1) then    
				stepTCLKin40_incomingMarker 		<= (others => '0');   
			end if;	
			
			--(1C)  MODULE RESET
			if(RESET_N = '0') then
				
				
				eventDetected 	<= '0';   
				eventEarlyError <= '0';						 
				
				E_markerOffsetPlusOne <= (others => '0');
				E_markerOffsetPlusTwo <= (others => '0');	 
				E_markerOffsetMinusOne 	<= (others => '0');	 
				E_markerOffsetMinusTwo	<= (others => '0');
				E_markerOffsetCenter	<= (others => '0');															
				
			--(1D)  NORMAL OPERATION
			else		                               
				--(1D.1) SECOND MARKER! ALIGN TO IT.
				if(eventLatch2 = '1' and eventLatch3 = '0' and needAlignment = '1') then 										
					stepTCLKin40_incomingMarker 		<= (others => '0');     			-- 		Marker reset the stepTCLKin40 in 1B 			 
					eventDetected 		<= '0';	 				
					
					E_markerOffsetPlusOne <= (others => '0');
					E_markerOffsetPlusTwo <= (others => '0');	 
					E_markerOffsetMinusOne 	<= (others => '0');	 
					E_markerOffsetMinusTwo	<= (others => '0');
					E_markerOffsetCenter	<= (others => '0');
				else					
					--(1D.2) RESET FLAGS IF DONE 
					if(markerDone = '1') then			        							
						eventDetected 		<= '0';	            							--     Marker is finished. Wait for next marker.
					end if;										  												   						
--				  	--(1D.3)**	MARKER DETECTION.
						if(stepTCLKin40_incomingMarker = flagDetectionEdge and eventLatch3 = '1') then	
						
						--(1D.3A)	EVENT MARKER BEFORE FINISH
							if(eventDetected = '1') then            							            	     
								eventEarlyError_Flag <= '1';
							end if;	  
							
							--(1D.3B)**EVENT DETECTED!	NOTIFY MODULE (2)!													
							eventDetected <= '1';			--	=> (2) Timestamp Emulator	 														
						end if;					 
				end if; 	   			  
				
				--(1E) Check Arrival Time  
				--(2E.2)EVENT MISALIGNMENT			 
				if (eventLatch2 = '1' and eventLatch3 = '0' and needAlignment = '0')	then
					if (stepTCLKin40_incomingMarker = 3) then	
						E_markerOffsetMinusOne 	<= E_markerOffsetMinusOne + 1;
					elsif (stepTCLKin40_incomingMarker = 2) then
						E_markerOffsetMinusTwo 	<=	E_markerOffsetMinusTwo + 1;	
					elsif (stepTCLKin40_incomingMarker = 1) then
						E_markerOffsetPlusTwo 	<= E_markerOffsetPlusTwo + 1;   
					elsif (stepTCLKin40_incomingMarker = 0) then
						E_markerOffsetPlusOne 	<= E_markerOffsetPlusOne + 1;	 	
					elsif (stepTCLKin40_incomingMarker = 4) then
						E_markerOffsetCenter	<= E_markerOffsetCenter + 1;	 	
					end if;	 	
				end if;			
			end if;	
		end if;	 
	end process;	 	  


	
--  --=======================
--	--(2) Time Stamp Emulator (TCLKMhz Reset of Timestamp)
--	--Input: 
--	--Reset: 
--	--Output:  
--	--=======================
	timeStamper : process (TCLK)
	begin  					
		if (rising_edge(TCLK)) then			   	 
-----------------------------------------------------------------			 
				eventOut	 	            <= '0';
				resetTimestampStrobe 		<= '0';								
				returnMarker 	            <= '0';		  
				
				
				if (event_start_fine_delay_latch /= EVENT_START_DELAY_FINE_TCLK and wait_event_fine_delay = '0') then   
					event_start_fine_delay_latch	<= EVENT_START_DELAY_FINE_TCLK;		
				end if;
				
		--(2A) SYSTEM RESET	
			if(RESET_N = '0') then   	
				wait_event_fine_delay			<= '0';	
				TIMESTAMP_OF					<= '0';
			 	markerDone						<= '0';
				startFineDelay					<= '0';	
				startLoopbackDelay 				<= '0';	
				counterOverflow 				<= '0';	 
				timeCounter 					<= (others => '0');	
				timestampDelayCounter40			<= (others => '0');
				fineDelayCounterTCLK 			<= (0 => '1' ,others => '0');
				event_start_fine_delay_latch	<= (others => '0');
				needAlignment_2					<= '1';
		--(2B) ALIGNMENT REQ
			elsif (alignment_req_rising_edge = '1')	then
				needAlignment_2 				<= '1';	
				needAlignment					<= '0';
				TIMESTAMP_OF					<= '0';		  
			else				 
				
		--(2C) Normal Operation
		--(2C.1) ALIGNMENT BY EVENTMARKER	--Event marker resets the domain transfer clocks		
			if(eventLatch2 = '1' and eventLatch3 = '0' and 				  
				needAlignment_2 = '1') then 	
				needAlignment_2	<= '0';
				needAlignment	<= '1';
			elsif(eventLatch2 = '1' and eventLatch3 = '0' and --Wait for second event marker to align (since first one will be the misaligned to forward detector)	  
				needAlignment = '1') then  	
				startFineDelay				<= '0';		
				counterOverflow 			<= '0';	 
				timeCounter 				<= (others => '0');	
				timestampDelayCounter40		<= (others => '0');
				fineDelayCounterTCLK 		<= (0 => '1' ,others => '0');	
				needAlignment  				<= '0';		
			end if;				  
													  	 
		 --(2C.2) Timestamping Counter
		 --================================
		 --(2C.2A) Reset Timestamp
			if(resetTimestampStrobe = '1') then		--Delay after Eventmarker received Ended!
				EVENT_WINDOW_TAG <= HEARTBEAT_EVENT_WINDOW_TAG;
				timeCounter 				<= (others => '0');	 
				resetTimestampStrobe 		<= '0';	  
				TIMESTAMP_OF				<= '0';	
			elsif (timeCounter = x"FFFFFFFF") then		 
				TIMESTAMP_OF				<= '1';	
			else									--Normal Operation
				timeCounter 				<= timeCounter + 1;
			end if;							   	  
			
	--------------------------------------------					
			--(2C.2B) WORKING ON MARKER REQUEST
			if markerDone = '1' then
				markerDone <= '0';
			end if;	   
			
			--(2C.2C) EVENT MANAGER
			if(eventDetected = '1' and markerDone  = '0') then					--(1) => (2) Event detected at (1)Domain Transfer				
				--(..2C.1) No Coarse Delay
				if(loopbackDelay = 0) then										--No Coarse delay
					markerDone 	<= '1';   
					--(..2C.1A) Loopback without delay
					if loopbackLatch = '1' and loopback_delay_en_latch = '0' then
						returnMarker 					<= '1';	  				--Return the marker immediately!
						resetTimestampStrobe     		<= '1';					--	   
					--(..2C.1B) Loopback with delay
					elsif loopbackLatch = '1' and loopback_delay_en_latch = '1' then	
						wait_event_fine_delay			<= '1';	
						startFineDelay					<= '1';				
						fineDelayCounterTCLK 			<= (0 => '1', others => '0');	
						if (unsigned(event_start_fine_delay_latch) = 0) then									  
							wait_event_fine_delay			<= '0';	
							returnMarker 					<= '1';	  				--Return the marker immediately!
							resetTimestampStrobe     		<= '1';		
						end if;
					--(..2C.1C)	 Event with delay
					elsif eventDetected = '1' and unsigned(event_start_fine_delay_latch) /= 0 then	   	 
						wait_event_fine_delay			<= '1';	
						fineDelayCounterTCLK 			<= (0 => '1', others => '0');	
						startFineDelay 	 				<= '1';  	   			--Wait before reset! Fine Delay
					--(..2C.1D)	 Event without delay
					elsif eventDetected = '1' and unsigned(event_start_fine_delay_latch) = 0 then
						resetTimestampStrobe     		<= '1';		  --Reset!
					end if;             
					
				--(..2C.2) Coarse Delay
				else 										   				   
					--(..2C.2A) 40Mhz counter (for Coarse Delay) 
					if(stepTCLKin40_incomingMarker = flagDetectionEdge + 1) then		   		--Increase counter for every reset.
						timestampDelayCounter40 		<= 	timestampDelayCounter40 + 1;   		--Counter in 40Mhz units
					end if;                         	
					
					--(..2C.2B)  
					if(stepTCLKin40_incomingMarker = edgeMinusOne and timestampDelayCounter40 = loopbackDelay) then		
							markerDone 					<= '1'; 
	                                              	
							if loopbackLatch = '1' then
								returnMarker 			<= '1';	   
							end if;	                	
							timestampDelayCounter40 	<= (others => '0');
					elsif (stepTCLKin40_incomingMarker = edgeMinusOne and 
							timestampDelayCounter40 = eventStartDelayCoarse40 and unsigned(event_start_fine_delay_latch) = 0) then
							resetTimestampStrobe 		<= '1';	  					
					elsif (stepTCLKin40_incomingMarker = edgeMinusOne and 
							timestampDelayCounter40 = eventStartDelayCoarse40 and unsigned(event_start_fine_delay_latch) /= 0) then
							if eventDetected = '1' then
								startFineDelay 	 		<= '1'; 	
								fineDelayCounterTCLK    <= (0=>'1',others=>'0');
							else				
								resetTimestampStrobe 	<= '1';
							end if;		
					end if;		 
					
				end if;		
			end if;			
			
		
	
	------Dynamic full marker shifts for alignment	
		if (startFineDelay = '1') then	   
					 
			if(fineDelayCounterTCLK 	= unsigned(event_start_fine_delay_latch)) then	
					wait_event_fine_delay			<= '0';	
					resetTimestampStrobe			<=  '1';   
					fineDelayCounterTCLK 			<= (others => '0');	
					startFineDelay 					<= '0';		   
					if (loopbackLatch 	= '1') then		 
						wait_event_fine_delay	<= '1';	
						startLoopbackDelay		<= '1';
						loopbackDelayCounter 	<= (0 => '1', others => '0');
					end if;
				elsif(fineDelayCounterTCLK 	< unsigned(event_start_fine_delay_latch)) then
					fineDelayCounterTCLK 			<=  fineDelayCounterTCLK + 1;	 
				else	
					wait_event_fine_delay			<= '0';	
					fineDelayCounterTCLK			<= (others => '0');	--If Counter error or sudden change of eventDelay. Reset.
					startFineDelay					<= '0';
				end if;
		end if;		 
		
	--Loopback wait stage
		if (startLoopbackDelay = '1') then
			if(loopbackDelayCounter 	= unsigned(event_start_fine_delay_latch)) then	
					wait_event_fine_delay			<= 	'0';	
					returnMarker					<=  '1';   
					fineDelayCounterTCLK 			<= (others => '0');	 
					loopbackDelayCounter 			<= (others => '0');	
					startLoopbackDelay 				<= '0';		   
				elsif(loopbackDelayCounter 	< unsigned(event_start_fine_delay_latch)) then
					loopbackDelayCounter 			<=  loopbackDelayCounter + 1;	 
				else	
					loopbackDelayCounter			<= (others => '0');	--If Counter error or sudden change of eventDelay. Reset.
					startFineDelay					<= '0';
				end if;
		end if;		
		
			
------------------------------------------				
			end if;
			
			
		end if;	   
	end process;				  

	--=======================	 
--	-- Returning Marker 	
--	------------------------- 
--Note: Returns the marker immediately.

	domainTransfer2: process (TCLK) 
	begin				   
		if (rising_edge(TCLK)) then
            --(3A) SYSTEM RESET/ALIGNMENT RESET							  
			if((eventLatch2 = '1' and eventLatch3 = '0' and needAlignment = '1')  or RESET_N = '0') then            
				stepTCLKin40_ReturnMarker				<= (others => '0');
				loopbackMarkerOut 						<= '0'; 
				domainState2 							<= "00";	-- To idle state
			--(3B) IDLE STATE -- Wait for Loopback
            elsif(domainState2 = "00") then
				if(returnMarker = '1') then							--Loopback detected
					loopbackMarkerOut 					<= '1';							 
					stepTCLKin40_ReturnMarker			<= stepTCLKin40_ReturnMarker + 1;
					domainState2 						<= "01";	--Marker ON	for (TCLK/40Mhz) cycles
				end if;	                
            --(3C) LOOPBACK TRANSFER ON
			elsif(domainState2 = "01") then							 
				stepTCLKin40_ReturnMarker				<= stepTCLKin40_ReturnMarker + 1;	 
				loopbackMarkerOut 						<= '1';
				
				if(stepTCLKin40_ReturnMarker = NUM_OF_TCLK_IN_40 - 1) then		  
					domainState2 						<= "10";  	--Start domain transfer and transmit to packet sender
				end if;		            
            --(3D) LOOPBACK TRANSFER FINISHED 
			elsif(domainState2 = "10") then
					stepTCLKin40_ReturnMarker			<= (others => '0');
					loopbackMarkerOut 					<= '0';
					domainState2 						<= "00";  	--Finish transmission, return to Idle
			end if;	  
		end if;
	end process;

end architecture;

