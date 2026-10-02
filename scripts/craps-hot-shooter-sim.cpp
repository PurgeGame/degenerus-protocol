// Analysis only. Build: g++ -O3 -std=c++20 scripts/craps-hot-shooter-sim.cpp -o /tmp/craps-hot
// Reuses the economic replica's dice, scatter, legal boards and legacy settlement for validation.
// Hot bonus pays ONLY profit on rolls X+1 onward, after surviving X rolls.
// Historical evaluate keeps +5% whole-hand rotation; evaluate-current uses +30% hot profit. No extra eligibility coin; no boost on principal or refunds.
// Uses production's current bust ranking, which differs from the older system simulator.
#define main existing_system_sim_main
#include "craps-high-water-system-sim.cpp"
#undef main
#include <cassert>
#include <fstream>
#include <sstream>
#include <set>

namespace hot {
bool ownHot = false;
bool jitter = false; // Sensitivity only: equal chance of 1% or (2*mean-1)%, always a bonus.
struct Hand {
    BoardMoney returned{}, profit{}, suffix{};
    int rolls{};
};
Hand profile(const Shooter& s, int threshold) {
    Hand h;
    std::array<bool, 10> live; live.fill(true);
    int point = 0;
    bool ended = false;
    auto pay = [&](int leg, i64 profit, i64 principal = 0) {
        h.returned[leg] += profit + principal;
        h.profit[leg] += profit;
        if (h.rolls > threshold) h.suffix[leg] += profit;
    };
    for (auto r : s.rolls) {
        ++h.rolls;
        int t = r.d1 + r.d2;
        if (point && t == 7) {
            if (live[9]) pay(9, 900, 1200);
            ended = true; break;
        }
        if (point) {
            constexpr int totals[] = {4,5,6,8,9,10};
            constexpr int pays[] = {2400,1800,1400,1400,1800,2400};
            for (int j=0;j<6;++j) if (t == totals[j]) pay(j+1,pays[j]);
            for (int j=7;j<=8;++j) if (live[j] && t == (j==7?4:8)) {
                if (r.d1==r.d2) pay(j,j==7?8400:10800);
                else live[j]=false;
            }
            if (t == point) {
                if (live[0]) pay(0,1200);
                live[9]=false; point=0;
            }
        } else if (t==7 || t==11) {
            if (live[0]) pay(0,1200);
            live[9]=false;
        } else if (t==12) live[0]=false;
        else if (t==2 || t==3) {
            live[0]=false;
            if (live[9]) { pay(9,900,1200); live[9]=false; }
        } else point=t;
    }
    if (!ended) for(int j=0;j<10;++j) if(live[j]) h.returned[j]+=1200;
    return h;
}
struct Cache {
    ShooterCache dice;
    int threshold;
    std::vector<Hand> hands;
    Cache(u64 seed,int x):dice(seed),threshold(x){}
    const Hand& get(int n) {
        while ((int)hands.size()<=n) hands.push_back(profile(dice.get(hands.size()),threshold));
        return hands[n];
    }
};
std::array<int,8> parsePcts(std::string s) {
    std::replace(s.begin(),s.end(),',',' '); std::istringstream in(s);
    std::array<int,8> a{}; for(auto& v:a) if(!(in>>v)||v<0||v>1000) throw std::runtime_error("need eight percentages, indexed by placed chips");
    return a;
}
Run settle(const ChipCounts& selected, Cache& cache, u64 seed, u64 owner,
           int seat,int heads,const std::array<int,8>& pcts,bool baseline=false,int depth=5) {
    ChipCounts board=selected;
    int placed=std::accumulate(board.begin(),board.end(),0);
    for(int i=0;i<10-placed;++i) ++board[keyed(seed,owner,i,0x5ca77eULL)%10];
    // Same 3000-FLIP bankroll as legacy validation, with exact 1200ths accounting.
    i64 chip = 3000/depth/10;
    i64 bankroll=3000*kMoneyUnits, goal=5*bankroll, stake=10*chip*kMoneyUnits;
    Run r; r.peakMoney=bankroll;
    bool qualified=false;
    int rotation=rotationTurn(seed,seat,heads);
    while(true) {
        if(!qualified && bankroll>=goal) {qualified=true;r.stop=Stop::Goal;}
        if(r.hands==kMaxHands || r.rolls>=kRollBudget) {r.capped=true;break;}
        int shift=escShiftOf(r.hands);
        i64 q=shift>=62?gEscCap:std::min(i64{1}<<shift,gEscCap), need=stake*q;
        if(qualified) {if(bankroll-goal<need)break;}
        else {
            if(bankroll*2<need)break;
            if(bankroll<need) {
                if(keyed(seed,owner,r.hands,0x5a7ULL)&1)bankroll*=2;
                else {bankroll=0;break;}
            }
        }
        const auto& h=cache.get(r.hands);
        i64 returned=0, profit=0, suffix=0;
        for(int j=0;j<10;++j) {
            returned+=board[j]*h.returned[j];
            profit+=board[j]*h.profit[j];
            suffix+=board[j]*h.suffix[j];
        }
        returned*=chip;profit*=chip;suffix*=chip;
        int rotate=r.hands==rotation?5:0;
        if(baseline) {
            int pct=keyed(seed,owner,r.hands,0xb0057ULL)%100 < (u64)kBoostChancePct[placed] ? kBoostUpliftBps[placed]/100 : 0;
            returned+=profit*(pct+rotate)/100;
        } else {
            int pct=pcts[placed];
            if(jitter && pct) pct=(keyed(seed,owner,r.hands,0xb0059ULL)&1)?1:2*pct-1;
            returned+=ownHot ? suffix*(pct+(r.hands==rotation?kOwnHotUpliftPct:0))/100 : (suffix*pct+profit*rotate)/100;
        }
        bankroll+=q*returned-need;
        ++r.hands;r.rolls+=h.rolls;r.units+=q;
        r.peakMoney=std::max(r.peakMoney,bankroll);
    }
    r.rawMoney=bankroll;r.paid=qualified?roundedPaid(bankroll,seed,owner):0;
    return r;
}
bool betterRun(const Run& a,const Run& b,u64 atie,u64 btie) {
    if(a.stop!=b.stop)return a.stop==Stop::Goal;
    if(a.stop==Stop::Bust) {
        if(a.hands!=b.hands)return a.hands>b.hands;
        bool ak=a.rawMoney>=kMoneyUnits,bk=b.rawMoney>=kMoneyUnits;
        if(ak!=bk)return ak;
    }
    i64 ap=a.peakMoney/kMoneyUnits,bp=b.peakMoney/kMoneyUnits;
    if(ap!=bp)return ap>bp;
    i64 ar=a.rawMoney/kMoneyUnits,br=b.rawMoney/kMoneyUnits;
    if(ar!=br)return ar>br;
    return atie>btie;
}
void validate(int n,u64 seed) {
    const auto boards=legalBoardChoices();
    for(int i=0;i<n;++i) {
        u64 s=keyed(seed,i),owner=keyed(s,1);
        Cache cache(s,i%25);
        const auto& shooter=cache.dice.get(0);
        Hand h=profile(shooter,i%25);
        Shooter prefix=shooter;
        prefix.rolls.resize(std::min(prefix.rolls.size(),std::size_t(i%25)));
        for(int j=0;j<10;++j) {
            BoardMoney b{};b[j]=1200;
            i64 raw=runHandMoney(b,shooter,false,0), p=runHandMoney(b,shooter,true,100)-raw;
            i64 pp=runHandMoney(b,prefix,true,100)-runHandMoney(b,prefix,false,0);
            assert(h.returned[j]==raw && h.profit[j]==p && h.suffix[j]==p-pp);
        }
        auto b=boards[keyed(s,2)%boards.size()];
        Terms t;t.bankroll=3000;t.round=600;t.goal=15000;
        gShooterBoostMode=ShooterBoostMode::Rotating; // explicit pre-duration rules
        Run old=settleBoardChoice(t,b,cache.dice,s,owner,0,40);
        Run now=settle(b,cache,s,owner,0,40,{},true);
        assert(old.rawMoney==now.rawMoney && old.peakMoney==now.peakMoney && old.hands==now.hands && old.rolls==now.rolls && old.paid==now.paid && old.stop==now.stop);
        gShooterBoostMode=ShooterBoostMode::Duration;
        Cache current(s,kHotAfterRolls);
        Run integrated=settleBoardChoice(t,b,current.dice,s,owner,0,40);
        ownHot=true;
        Run profiled=settle(b,current,s,owner,0,40,{30,25,20,18,14,10,7,5});
        ownHot=false;
        assert(integrated.rawMoney==profiled.rawMoney && integrated.peakMoney==profiled.peakMoney && integrated.hands==profiled.hands && integrated.rolls==profiled.rolls && integrated.paid==profiled.paid && integrated.stop==profiled.stop);
    }
    // Boundary: roll 1 establishes 6, roll 2 wins place 6, roll 3 sevens out.
    Shooter script{{{3,3},{3,3},{3,4}},true};
    assert(profile(script,1).suffix[3]==1400);
    assert(profile(script,2).suffix[3]==0);
    // A surviving Don't Pass can earn its PROFIT on the seven-out after the threshold.
    Shooter dark{{{2,2},{3,4}},true};
    assert(profile(dark,1).suffix[9]==900);
    std::cout<<"validated "<<n<<" hands x 10 legs and complete baseline runs; cutoff and principal assertions passed\n";
}
struct Stat {
    long double paid{}, paid2{},goal{},peak25{},peak120{},capped{};
    std::array<long double,6> wins{};
    void add(const Run&r) {
        long double p=r.paid/3000.L;paid+=p;paid2+=p*p;goal+=r.stop==Stop::Goal;
        peak25+=r.peakMoney>=3000*kMoneyUnits*25;peak120+=r.peakMoney>=3000*kMoneyUnits*120;capped+=r.capped;
    }
};
void emit(const std::string& label,int id,const ChipCounts&b,const Stat&s,int n) {
    long double mean=s.paid/n, se=std::sqrt(std::max(0.L,(s.paid2-n*mean*mean)/(n-1)/n));
    std::cout<<label<<'\t'<<id<<'\t'<<std::accumulate(b.begin(),b.end(),0)<<'\t'<<boardText(b)<<'\t'<<n<<'\t'<<100*mean<<'\t'<<196*se<<'\t'<<100*s.goal/n<<'\t'<<100*s.peak25/n<<'\t'<<100*s.peak120/n<<'\t'<<s.capped;
    for(auto w:s.wins)std::cout<<'\t'<<100*w/n;
    std::cout<<'\n';
}
void header(){std::cout<<"mode\tid\tplaced\tboard\tsamples\trtp_pct\trtp_ci95_half_pp\tgoal_pct\tpeak25_pct\tpeak120_pct\tcap_count\twin_blank_pct\twin_sharp_pct\twin_mix_pct\twin_dark_pct\twin_pass_pct\twin_adaptive_pct\n";}
void profiles(int n,u64 seed) {
    std::cout<<"threshold\tsurvived_pct\tleg\tmean_return\tmean_profit\tmean_suffix_profit\tsuffix_fraction\n";
    for(int x:{8,10,12,16,20}) {
        BoardMoney returns{},profits{},suffix{};int reached=0;
        for(int i=0;i<n;++i) {
            ShooterCache dice(keyed(seed,i));const auto&s=dice.get(0);auto h=profile(s,x);
            reached+=(int)s.rolls.size()>x;
            for(int j=0;j<10;++j){returns[j]+=h.returned[j];profits[j]+=h.profit[j];suffix[j]+=h.suffix[j];}
        }
        for(int j=0;j<10;++j)std::cout<<x<<'\t'<<100.L*reached/n<<'\t'<<j<<'\t'<<returns[j]/(1200.L*n)<<'\t'<<profits[j]/(1200.L*n)<<'\t'<<suffix[j]/(1200.L*n)<<'\t'<<1.L*suffix[j]/profits[j]<<'\n';
    }
}
std::vector<int> selectedIds(const std::vector<ChipCounts>& boards,const std::string& path) {
    std::vector<int> ids;
    if(path=="all") {for(int i=0;i<(int)boards.size();++i)ids.push_back(i);}
    else if(path=="probes") {
        std::set<int> keep;
        for(int placed=0;placed<=7;++placed) for(int leg=0;leg<10;++leg) {
            ChipCounts b{};int left=placed;
            // Concentrate in a selected leg, then other legal legs, retaining endpoints at every tier.
            for(int step=0;step<10 && left;++step) {
                int j=(leg+step)%10;
                if((j==0&&b[9])||(j==9&&b[0]))continue;
                b[j]=std::min(left,3);left-=b[j];
            }
            auto it=std::find(boards.begin(),boards.end(),b);assert(it!=boards.end());keep.insert(it-boards.begin());
        }
        for(auto s:{Strategy::Sharp4,Strategy::FairSpread,Strategy::Mixed,Strategy::Pass,Strategy::Blank,Strategy::Hardways,Strategy::Dark,Strategy::Bounty}) {
            auto b=pickedCounts(s);auto it=std::find(boards.begin(),boards.end(),b);assert(it!=boards.end());keep.insert(it-boards.begin());
        }
        ids.assign(keep.begin(),keep.end());
    } else {std::ifstream f(path);int id;while(f>>id){if(id<0||id>=(int)boards.size())throw std::runtime_error("bad id");ids.push_back(id);}}
    if(ids.empty())throw std::runtime_error("empty board set");return ids;
}
void evaluate(int n,u64 seed,int threshold,const std::array<int,8>&pcts,const std::string&path,bool baseline,bool fields,int heads) {
    auto boards=legalBoardChoices();auto ids=selectedIds(boards,path);std::vector<Stat> stats(ids.size());
    std::cerr<<"boards="<<boards.size()<<" candidates="<<ids.size()<<" samples="<<n<<" threshold="<<threshold<<" baseline="<<baseline<<" heads="<<heads<<'\n';
    const std::array<Strategy,8> mixed{Strategy::Blank,Strategy::Sharp4,Strategy::FairSpread,Strategy::Mixed,Strategy::Pass,Strategy::Hardways,Strategy::Dark,Strategy::Bounty};
    for(int i=0;i<n;++i) {
        u64 s=keyed(seed,i),owner=keyed(s,0xca1ULL),tie=keyed(s,heads-1,0x71eULL);
        Cache cache(s,threshold);
        std::array<Run,6> best;std::array<u64,6> ties{};
        if(fields)for(int f=0;f<6;++f)for(int seat=0;seat<heads-1;++seat) {
            Strategy strategy=f==0?Strategy::Blank:f==1?Strategy::Sharp4:f==2?mixed[seat%mixed.size()]:f==3?Strategy::Dark:f==4?Strategy::Pass:
                std::array<Strategy,4>{Strategy::Dark,Strategy::Bounty,Strategy::Pass,Strategy::Sharp4}[seat%4];
            u64 pk=keyed(s,seat,0x1ac0ULL),t=keyed(s,seat,0x71eULL);
            auto r=settle(pickedCounts(strategy),cache,s,pk,seat,heads,pcts,baseline);
            if(seat==0||betterRun(r,best[f],t,ties[f])){best[f]=r;ties[f]=t;}
        }
        for(std::size_t j=0;j<ids.size();++j) {
            auto r=settle(boards[ids[j]],cache,s,owner,heads-1,heads,pcts,baseline);
            stats[j].add(r);
            if(fields)for(int f=0;f<6;++f)stats[j].wins[f]+=betterRun(r,best[f],tie,ties[f]);
        }
    }
    header();for(std::size_t j=0;j<ids.size();++j)emit(baseline?"baseline":"hot"+std::to_string(threshold)+(ownHot?"_own30":"")+(jitter?"_jitter":""),ids[j],boards[ids[j]],stats[j],n);
}
}
int main(int argc,char**argv) {
    try {
        if(argc<4)throw std::runtime_error("validate|profiles|evaluate SAMPLES SEED [threshold pcts ids|all|probes baseline fields heads]");
        std::cout<<std::fixed<<std::setprecision(6);
        std::string command=argv[1];int n=std::stoi(argv[2]);u64 seed=std::stoull(argv[3]);
        hot::ownHot = command == "evaluate-current";
        if(n<2)throw std::runtime_error("samples must be >=2");
        if(argc==11)hot::jitter=std::stoi(argv[10]);
        if(command=="validate")hot::validate(n,seed);
        else if(command=="profiles")hot::profiles(n,seed);
        else if((command=="evaluate"||command=="evaluate-current")&&(argc==10||argc==11))hot::evaluate(n,seed,std::stoi(argv[4]),hot::parsePcts(argv[5]),argv[6],std::stoi(argv[7]),std::stoi(argv[8]),std::stoi(argv[9]));
        else throw std::runtime_error("bad command");
    }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
}
