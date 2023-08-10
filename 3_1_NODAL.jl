using Gurobi,JuMP
using Plots, Random, Printf, XLSX, CSV, DataFrames, Distributions

# SETS

CONVENTIONAL_GENERATORS=["G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]
G=length(CONVENTIONAL_GENERATORS)

WIND_FARMS=["W1","W2","W3","W4"]
W=length(WIND_FARMS)

DEMANDS=["D1","D2","D3","D4","D5","D6","D7","D8","D9","D10","D11","D12","D13","D14","D15","D16","D17"]
D=length(DEMANDS)

WIND_AND_GENERATOR=["W1","W2","W3","W4","G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]

TIME_SLOT=["00-01","01-02","02-03","03-04","04-05","05-06","06-07","07-08","08-09","09-10","10-11","11-12","12-13","13-14","14-15","15-16","16-17","17-18","18-19","19-20","20-21","21-22","22-23","23-24"]
T=length(TIME_SLOT)

NODES=["N1","N2","N3","N4","N5","N6","N7","N8","N9","N10","N11","N12","N13","N14","N15","N16","N17","N18","N19","N20","N21","N22","N23","N24"]
M=length(NODES)
N=M                  


# DATA

# Conventional generators [length: 12]
Location_G = [1 2 7 13 15 15 16 18 21 22 23 23] # node
Production_cost_G = [13.32 13.32 20.7 20.93 26.11 10.52 10.52 6.02 5.47 7 10.52 10.89] #[$/MW]
Capacity_G = [106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW

# Wind farms [length: 4]
Location_W = [3 5 16 21] #node
Installed_capacity_W= [500 500 300 300] #[MW]
Day_ahead_forecast_W = [120.54 115.52 53.34 38.16] #[MW]
Cost_of_energy_wind=0


# Wind farm and generators together [length: 4+17=21]

WIND_AND_GENERATOR=["W1","W2","W3","W4","G1","G2","G3","G4","G5","G6","G7","G8","G9","G10","G11","G12"]
WG=length(WIND_AND_GENERATOR)
Location_WG = [3 5 16 21 1 2 7 13 15 15 16 18 21 22 23 23] # node
Production_cost_WG = [0 0 0 0 13.32 13.32 20.7 20.93 26.11 10.52 10.52 6.02 5.47 7 10.52 10.89] #[$/MW]
PROD_Capacity_WG = [500 500 300 300 106.4 106.4 245 413.7 42 108.5 108.5 280 280 210 217 245] #MW

nd=Normal(0,0.3)
PROD_Capacity_WG_t=zeros(WG,T)
wind_variability=zeros(WG,T)
for wg=1:W
  wind_variability[wg,:]=rand(nd,T)
end
for t=1:T
for wg=W+1:WG
  wind_variability[wg,t]=0
end
end
capacity_factor=[0.31 0.33 0.34 0.36 1 1 1 1 1 1 1 1 1 1 1 1]
for t=1:T
  for wg=1:WG
    PROD_Capacity_WG_t[wg,t]=PROD_Capacity_WG[wg]*capacity_factor[wg]+PROD_Capacity_WG[wg]*wind_variability[wg,t]*capacity_factor[wg]
  end
end


# NODES

nodes_capacity=[

    0 175 175 0 350 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0          
    175 0 0 175 0 175 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0          
    175 0 0 0 0 0 0 0 175 0 0 0 0 0 0 0 0 0 0 0 0 0 0 400          
    0 175 0 0 0 0 0 0 175 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0            
    175 0 0 0 0 0 0 0 0 350 0 0 0 0 0 0 0 0 0 0 0 0 0 0            
    0 175 0 0 0 0 0 0 0 175 0 0 0 0 0 0 0 0 0 0 0 0 0 0          
    0 0 0 0 0 0 0 350 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0            
    0 0 0 0 0 0 350 0 175 175 0 0 0 0 0 0 0 0 0 0 0 0 0 0         
    0 0 175 175 0 0 0 175 0 0 400 400 0 0 0 0 0 0 0 0 0 0 0 0   
    0 0 0 0 350 175 0 175 0 0 400 400 0 0 0 0 0 0 0 0 0 0 0 0      
    0 0 0 0 0 0 0 0 400 400 0 0 500 500 0 0 0 0 0 0 0 0 0 0      
    0 0 0 0 0 0 0 0 400 400 0 0 500 0 0 0 0 0 0 0 0 0 500 0       
    0 0 0 0 0 0 0 0 0 0 500 500 0 0 0 0 0 0 0 0 0 0 250 0        
    0 0 0 0 0 0 0 0 0 0 500 0 0 0 0 250 0 0 0 0 0 0 0 0            
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 500 0 0 0 0 400 0 0 500         
    0 0 0 0 0 0 0 0 0 0 0 0 0 250 500 0 500 0 500 0 0 0 0 0        
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 500 0 500 0 0 0 500 0 0        
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 500 0 0 0 1000 0 0 0          
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 500 0 0 0 1000 0 0 0 0           
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1000 0 0 1000 0         
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 400 0 0 1000 0 0 0 500 0 0        
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 500 0 0 0 500 0 0 0            
    0 0 0 0 0 0 0 0 0 0 0 500 250 0 0 0 0 0 0 1000 0 0 0 0        
    0 0 400 0 0 0 0 0 0 0 0 0 0 0 500 0 0 0 0 0 0 0 0 0            
]

nodes_sus=[

    0 0.0146 0.2253 0 0.0907 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0              #1   
    0.0146 0 0 0.1356 0 0.205 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0               #2
    0.2253 0 0 0 0 0 0 0 0.1271 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.084               #3
    0 0.1356 0 0 0 0 0 0 0.111 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0                    #4
    0.0907 0 0 0 0 0 0 0 0 0.094 0 0 0 0 0 0 0 0 0 0 0 0 0 0                    #5
    0 0.205 0 0 0 0 0 0 0 0.0642 0 0 0 0 0 0 0 0 0 0 0 0 0 0                    #6
    0 0 0 0 0 0 0 0.0652 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0                        #7
    0 0 0 0 0 0 0.0652 0 0.1762 0.1762 0 0 0 0 0 0 0 0 0 0 0 0 0 0              #8
    0 0 0.1271 0.111 0 0 0 0.1762 0 0 0.084 0.084 0 0 0 0 0 0 0 0 0 0 0 0       #9
    0 0 0 0 0.094 0.0642 0 0.1762 0 0 0.084 0.084 0 0 0 0 0 0 0 0 0 0 0 0       #10
    0 0 0 0 0 0 0 0 0.084 0.084 0 0 0.0488 0.0426 0 0 0 0 0 0 0 0 0 0           #11
    0 0 0 0 0 0 0 0 0.084 0.084 0 0 0.0488 0 0 0 0 0 0 0 0 0 0.0985 0           #12
    0 0 0 0 0 0 0 0 0 0 0.0488 0.0488 0 0 0 0 0 0 0 0 0 0 0.0884 0              #13
    0 0 0 0 0 0 0 0 0 0 0 0.0426 0 0 0 0.0594 0 0 0 0 0 0 0 0                   #14
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0172 0 0 0 0 0.0249 0 0 0.0529              #15
    0 0 0 0 0 0 0 0 0 0 0 0 0 0.0594 0.0172 0 0.0263 0 0.0234 0 0 0 0 0         #16
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0263 0 0.0143 0 0 0 0.1069 0 0              #17
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0143 0 0 0.0132 0 0 0                   #18
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0234 0 0 0 0.0203 0 0 0 0                   #19
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0203 0 0 0.0112 0                   #20
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.0249 0 0 0.0132 0 0 0 0.0692 0 0              #21
    0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0.1069 0 0 0 0.0692 0 0 0                   #22
    0 0 0 0 0 0 0 0 0 0 0 0.0985 0.0884 0 0 0 0 0 0 0.0112 0 0 0 0              #23
    0 0 0.084 0 0 0 0 0 0 0 0 0 0 0 0.0529 0 0 0 0 0 0 0 0 0                    #24
]

BB=zeros(N,M)

for n=1:N
    for m=1:M
        if nodes_sus[n,m]!=0
BB[n,m]=1/nodes_sus[n,m]
        end
    end
end

# Demand  [length: 17]
Consumption_demand = [84 75 139 58 55 106 97 132 135 150 205 150 245 77 258 141 100] #MW
time_demand=[0.2 0.2 0.2 0.3 0.4 0.6 0.9 1.1 1.1 1 0.9 0.8 0.9 1 0.9 1.1 1 1.2 1.1 0.8 0.8 0.8 0.6 0.4]
Location_demand = [1 2 3 4 5 6 7 8 9 10 13 14 15 16 18 19 20] #node


Bid_Price_demand=zeros(D,T)

for t=1:T
Random.seed!(t)
Bid_Price_demand[:,t] = sort(rand(15:100,D),rev=true)  # bid price random array
end

demand_fin=zeros(D,T)
for t=1:T
  for d=1:D
    demand_fin[d,t]=Consumption_demand[d]*time_demand[t]
  end
end

# electrolyzer

kg_to_MWh=1/18
electrolyzer_capacity=zeros(WG)
min_H2_per_electro=30000


for wg=1:W
    if sum(PROD_Capacity_WG_t[wg,t] for t=1:T) >= min_H2_per_electro*kg_to_MWh   # if with the DA it cannot reach te minimum to be activated then it is forced to 0
    electrolyzer_capacity[wg]=Installed_capacity_W[wg]/2
    end
end


# Model

C1 = Model(Gurobi.Optimizer)

@variable(C1,x_wg[1:WG,1:T]>=0)                                 # power production per each wind farm and generator to match the demand (doesn't take into accoutn the power for electrolysis)
@variable(C1,demand_covered[1:D,1:T]>=0)                        # demand covered per each time slot (cosidering that not all the demand is always covered)
@variable(C1,H2_electrolyzer[1:WG,1:T]>=0)                      # kg of H2 produced of each electrolyzer at each time slot
@variable(C1, power_flow[1:N,1:M,1:T])                          # power flow = B(m,n)( voltage angle(n)-voltage angle(m))
@variable(C1, voltage_angle[1:N,1:T])


@constraint(C1,[wg=1:WG,t=1:T], x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh<=PROD_Capacity_WG_t[wg,t])                          # general capacity constraint including H2
@constraint(C1,[wg=1:WG,t=1:T], H2_electrolyzer[wg,t]*kg_to_MWh <= electrolyzer_capacity[wg])                                # electrolyzer: h2 produced just by wind farm  [cap=0 in generators]

@constraint(C1,[d=1:D,t=1:T], demand_covered[d,t]<=demand_fin[d,t])                                                    # the demand supplied can cover less than the actual demand based on the bids but it cannot exceed it

@constraint(C1,[wg=1:WG],sum(H2_electrolyzer[wg,t] for t=1:T) >= min_H2_per_electro*(electrolyzer_capacity[wg]==0 ? 0 : 1))   # the electrolyzer has to produce more than the amount SET (30 tons)
@constraint(C1, sum(H2_electrolyzer[wg,t] for wg=1:WG,t=1:T)>=2*min_H2_per_electro)                                          # at least 2 electrolyzer - one electrolyzer doesnt have enough capacity to cover the minimum amount (?)


@constraint(C1,[n=1:N,m=1:M,t=1:T], power_flow[n,m,t] == BB[n,m]*(voltage_angle[n,t]-voltage_angle[m,t]))
@constraint(C1, [t=1:T],voltage_angle[1,t] == 0)
@constraint(C1,cap[n=1:N,m=1:M,t=1:T], -nodes_capacity[n,m] <= power_flow[n,m,t] <=nodes_capacity[n,m])
@constraint(C1, power_balance[n=1:N,t=1:T],
                                                   - sum(demand_covered[d,t]*(Location_demand[d]==n ? 1 : 0) for d=1:D)          # if the demand is located in the right znes then it is taken into account otherwise not
                                                  + sum(x_wg[wg,t]*(Location_WG[wg]==n ? 1 : 0) for wg=1:WG)                     # the same principle is used for the production
                                                  - sum(power_flow[n,m,t] for m=1:M) == 0)


@objective(C1,Max, sum(Bid_Price_demand[d,t]*demand_covered[d,t] for d=1:D,t=1:T) - sum(Production_cost_WG[wg]*(x_wg[wg,t] + H2_electrolyzer[wg,t]*kg_to_MWh) for wg=1:WG,t=1:T))

optimize!(C1)

########################## printing stuff ##################################


# for t=1:T
#     println("Market Price (",TIME_SLOT[t],"): ", @sprintf("%.2f", market_price[t]) , " \$/MWh")    # market price
# end

market_price_nodal=zeros(N,T)

for n=1:N
    for t=1:T
        market_price_nodal[n,t]=value(dual.(power_balance[n,t]))
    end
end

t=1  #            TIME SLOT PRINTED

for n=1:N
    println("MARKET PRICE AT TIME SLOT ", TIME_SLOT[t], " at ", NODES[n],  ": ", @sprintf("%.2f", market_price_nodal[n,t]) , " \$/MWh" )
end

println("\n")

for n=1:N
    for m=1:M
        if value(power_flow[n,m,t]) != 0
        println("power flow from node ", NODES[n], " to node ", NODES[m],": ",  @sprintf("%.2f", value(power_flow[n,m,t])), " - capacity: ",  @sprintf("%.2f", value(nodes_capacity[n,m])))
    end
end
end

println("\n")

for n=1:N
    for wg=1:WG
    if n==Location_WG[wg]
        println("Generation of power to the grid of ", WIND_AND_GENERATOR[wg], " from node ", NODES[n], ": ",  @sprintf("%.2f", value(x_wg[wg,1])), " - Power for hydrogen: ",@sprintf("%.2f", value(H2_electrolyzer[wg,1])*kg_to_MWh) )
    end
end
end

println("\n")

for n=1:N
    for d=1:D
    if n==Location_demand[d]
        println("Demand covered of ", DEMANDS[d], " from node ", NODES[n], ": ",  @sprintf("%.2f", value(demand_covered[d,t])), " MWh - bid price: ", @sprintf("%.2f", Bid_Price_demand[d,t]), " \$/MWh" )
    end
end
end


println("\n")

println("SOCIAL WELFARE : $(objective_value(C1)) \$")

